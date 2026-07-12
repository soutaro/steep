module Steep
  module TypeInference
    # Walks a parsed Ruby AST and, for each method that returns a local variable
    # whose attributes were assigned self-rooted paths, records those
    # attribute→path aliases on the *return value* (felixefelip/steep#62):
    #
    #   def build
    #     record = Assignment.new
    #     record.post = owner        # record.post <- self.owner
    #     record
    #   end
    #   # => { "Proxy#build" => { post: [:owner] } }   (build.post is self.owner)
    #
    # Consumed via `Contracts::AliasResolver` so a caller's `x = build` lets
    # `x.post.user` be rooted at `self.owner.user`. Purely syntactic and
    # conservative: only a method whose last statement is a bare local var, with
    # direct `that_local.attr = <self path>` writes, qualifies.
    class ReturnAliasAnalyzer
      def self.analyze(node)
        new.analyze(node)
      end

      def initialize
        @result = {} #: Hash[String, Hash[Symbol, Array[Symbol]]]
      end

      def analyze(node)
        return @result unless node.is_a?(::Parser::AST::Node)
        walk(node, nesting: [])
        @result
      end

      private

      def walk(node, nesting:)
        case node.type
        when :class
          const_node, _super, body = node.children
          name = const_to_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          register_class(body, new_nesting) if body && name
          walk(body, nesting: new_nesting) if body
        when :module
          const_node, body = node.children
          name = const_to_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk(body, nesting: new_nesting) if body
        else
          node.children.each { |c| walk(c, nesting: nesting) if c.is_a?(::Parser::AST::Node) }
        end
      end

      def register_class(body, nesting)
        class_name = nesting.join("::")
        each_stmt(body) do |stmt|
          next unless stmt.type == :def
          mname, _args, mbody = stmt.children
          readers = returned_attr_paths(mbody, class_name)
          @result["#{class_name}##{mname}"] = readers unless readers.empty?
        end
      end

      # `{ attr => path }` for the attributes of the method's returned local.
      def returned_attr_paths(mbody, class_name)
        result = {} #: Hash[Symbol, Array[Symbol]]
        local = returned_local(mbody)
        return result unless local

        Contracts::AliasResolver.local_attr_aliases(mbody, class_name: class_name, return_aliases: {}).each do |(l, attr), path|
          result[attr] = path if l == local
        end
        result
      end

      # The local variable a method body evaluates to: `return x` or a trailing
      # bare `x`.
      def returned_local(body)
        return nil unless body.is_a?(::Parser::AST::Node)
        node = body.type == :begin || body.type == :kwbegin ? body.children.last : body
        return nil unless node.is_a?(::Parser::AST::Node)
        node = node.children.first if node.type == :return
        return nil unless node.is_a?(::Parser::AST::Node) && node.type == :lvar
        node.children.first
      end

      def each_stmt(body)
        return unless body.is_a?(::Parser::AST::Node)
        stmts = body.type == :begin || body.type == :kwbegin ? body.children : [body]
        stmts.each { |s| yield s if s.is_a?(::Parser::AST::Node) }
      end

      def const_to_name(node)
        return nil unless node.is_a?(::Parser::AST::Node) && node.type == :const
        scope, name = node.children
        case scope&.type
        when nil, :cbase
          name.to_s
        when :const
          prefix = const_to_name(scope)
          prefix ? "#{prefix}::#{name}" : name.to_s
        end
      end
    end
  end
end
