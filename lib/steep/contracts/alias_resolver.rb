module Steep
  module Contracts
    # Resolves, within a single method body, which `local.attr` reads project a
    # self-rooted path — so a deref through the local (`record.post.user`) can be
    # rooted at `self` (`self.owner.user`) for precondition inference and
    # narrowing (felixefelip/steep#62). Two sources of `local.attr => path`:
    #
    #   1. a direct write `local.attr = <self path>` (`record.post = owner`);
    #   2. `local = <self-call>` where the callee return-aliases a reader to a
    #      self path (`record = build`, with `build` returning a record whose
    #      `post` is `self.owner`).
    #
    # Purely syntactic; paths are arrays of method symbols (`self.owner` → [:owner]).
    module AliasResolver
      module_function

      # `self.a.b.c` → [:a, :b, :c]; nil unless `node` is a pure self-rooted
      # send chain (no args, rooted at `self` or implicit self).
      def self_path(node)
        return nil unless node.is_a?(::Parser::AST::Node) && node.type == :send
        methods = [] #: Array[Symbol]
        current = node #: Parser::AST::Node?
        while current.is_a?(::Parser::AST::Node) && current.type == :send
          recv, mname, *args = current.children
          return nil unless args.empty?
          methods.unshift(mname)
          current = recv
        end
        return nil unless current.nil? || (current.is_a?(::Parser::AST::Node) && current.type == :self)
        methods
      end

      # `foo` / `self.foo` (no args) → :foo; nil otherwise.
      def self_call_method(node)
        return nil unless node.is_a?(::Parser::AST::Node) && node.type == :send
        recv, mname, *args = node.children
        return nil unless args.empty?
        return nil unless recv.nil? || (recv.is_a?(::Parser::AST::Node) && recv.type == :self)
        mname
      end

      # { [local_sym, attr_sym] => [path_syms] } for a method body. `class_name`
      # + `return_aliases` ("Class#method" => { reader => path }) drive the
      # `local = <self-call>` case; pass an empty hash to consider only direct
      # `local.attr = <self path>` writes.
      def local_attr_aliases(body, class_name:, return_aliases:)
        aliases = {} #: Hash[[Symbol, Symbol], Array[Symbol]]
        walk(body) do |node|
          case node.type
          when :send
            recv, mname, *args = node.children
            next unless recv.is_a?(::Parser::AST::Node) && recv.type == :lvar
            next unless mname.to_s.end_with?("=") && args.size == 1
            path = self_path(args[0])
            next unless path
            aliases[[recv.children[0], mname.to_s.delete_suffix("=").to_sym]] = path
          when :lvasgn
            local, rhs = node.children
            method = self_call_method(rhs)
            next unless method
            readers = return_aliases["#{class_name}##{method}"]
            next unless readers
            readers.each { |reader, path| aliases[[local, reader]] = path }
          end
        end
        aliases
      end

      def walk(node, &block)
        return unless node.is_a?(::Parser::AST::Node)
        yield node
        node.children.each { |c| walk(c, &block) }
      end
    end
  end
end
