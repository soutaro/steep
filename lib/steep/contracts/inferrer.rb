module Steep
  module Contracts
    class Inferrer
      def self.infer(source, typing, return_aliases:)
        new(source, typing, return_aliases: return_aliases).infer
      end

      def initialize(source, typing, return_aliases:)
        @source = source
        @typing = typing
        @return_aliases = return_aliases
        @diagnostics_by_node = nil
      end

      def infer
        return [] unless @source.node

        results = {}
        walk_classes(@source.node, nesting: []) do |def_node, class_name|
          next unless def_node.type == :def

          obligations = collect_obligations(def_node, class_name)
          next if obligations.empty?

          key = "#{class_name}##{def_node.children[0]}"
          merged = (results[key] || []) + obligations
          results[key] = dedupe(merged)
        end

        results.map do |key, requires|
          type_name, separator, method = key.partition(/[#.]/)
          MethodContract.new(
            type_name: type_name,
            method_name: method.to_sym,
            singleton: separator == ".",
            requires: requires
          )
        end
      end

      private

      def walk_classes(node, nesting:, &block)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class
          const_node, _super, body = node.children
          name = extract_const_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk_classes(body, nesting: new_nesting, &block) if body
        when :module
          const_node, body = node.children
          name = extract_const_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk_classes(body, nesting: new_nesting, &block) if body
        when :def
          unless nesting.empty?
            yield node, nesting.join("::")
          end
        when :begin, :kwbegin
          node.children.each { |child| walk_classes(child, nesting: nesting, &block) }
        when :sclass
          walk_classes(node.children[1], nesting: nesting, &block)
        else
          node.children.each do |child|
            walk_classes(child, nesting: nesting, &block)
          end
        end
      end

      def extract_const_name(node)
        return nil unless node.is_a?(Parser::AST::Node)
        case node.type
        when :const
          parent, name = node.children
          parent_name = parent ? extract_const_name(parent) : nil
          parent_name ? "#{parent_name}::#{name}" : name.to_s
        end
      end

      def collect_obligations(def_node, class_name)
        body = def_node.children[2]
        return [] unless body

        body_range = node_range(def_node)
        # felixefelip/steep#62: `{ [local, attr] => [path_syms] }` so a deref
        # through a local aliased to a self path (`record.post` <- `self.owner`,
        # directly or via `record = build`) is rooted at `self`.
        aliases = Contracts::AliasResolver.local_attr_aliases(body, class_name: class_name, return_aliases: @return_aliases)
        obligations = []

        no_method_errors_within(body_range).each do |error|
          call_node = error.node
          next unless call_node && call_node.is_a?(Parser::AST::Node)

          receiver = call_node.children[0]
          expr = self_path_to_expr(receiver, aliases)
          next unless expr

          obligations << Predicate::NotNil.new(expr)
        end

        obligations
      end

      def no_method_errors_within(range)
        @typing.errors.select do |error|
          next false unless error.is_a?(Steep::Diagnostic::Ruby::NoMethod)
          loc = error.node&.location&.expression
          loc && range.cover?(loc.begin_pos)
        end
      end

      def node_range(node)
        loc = node.location.expression
        loc.begin_pos..loc.end_pos
      end

      def self_path_to_expr(node, aliases = {})
        return nil unless node.is_a?(Parser::AST::Node)
        return nil unless node.type == :send

        methods = []
        current = node
        while current.is_a?(Parser::AST::Node) && current.type == :send
          recv, mname, *args = current.children
          return nil unless args.empty?

          # `local.attr` aliased to a self path (`record.post` ← `self.owner`):
          # splice that self path in and chain the methods gathered so far on top
          # (`record.post.user` → `self.owner.user`).
          if recv.is_a?(Parser::AST::Node) && recv.type == :lvar &&
              (path = aliases[[recv.children[0], mname]])
            full = path + methods
            return Expr::Send.new(receiver: Expr::SelfRef.instance, method: full.first, chain: full.drop(1))
          end

          methods.unshift(mname)
          current = recv
        end

        unless current.nil? || (current.is_a?(Parser::AST::Node) && current.type == :self)
          return nil
        end

        head = methods.shift
        Expr::Send.new(receiver: Expr::SelfRef.instance, method: head, chain: methods)
      end

      def dedupe(predicates)
        seen = {}
        predicates.each do |pred|
          key = predicate_key(pred)
          seen[key] ||= pred
        end
        seen.values
      end

      def predicate_key(pred)
        case pred
        when Predicate::NotNil
          [:not_nil, expr_key(pred.expr)]
        end
      end

      def expr_key(expr)
        case expr
        when Expr::SelfRef then [:self]
        when Expr::Send then [:send, expr_key(expr.receiver), expr.method, expr.chain]
        end
      end
    end
  end
end
