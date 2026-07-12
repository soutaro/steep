module Steep
  module TypeInference
    # Walks a parsed Ruby AST and, for each method whose return value constructs
    # an owner-capturing proxy, records which of the proxy's readers is the
    # *call's own receiver*:
    #
    #   class Post
    #     def assignments
    #       Proxy.new(Assignment, self)   # Proxy binds `owner` to arg 1 = self
    #     end
    #   end
    #   # => { "Post#assignments" => Set[:owner] }
    #
    # i.e. `post.assignments.owner` is `post`. Consumed by `TypeConstruction` at
    # a precondition call site to collapse `<recv>.<method>.<reader>` back to
    # `<recv>` (felixefelip/steep#62): `@post.assignments.create!`'s inherited
    # `not_nil self.owner.user` reduces to `not_nil @post.user`, provable via
    # `@post`'s marker — which is what lets the proxy's `create!`/`build`
    # contracts be enforced at an external call site.
    #
    # Reuses the `ConstructorBindingAnalyzer` result (reader→param index) to
    # decide which returned-proxy reader maps to the constructor's `self` arg.
    # Purely syntactic and conservative: only a return that is exactly
    # `K.new(args)` with a `self` argument at a bound reader's index qualifies.
    class ReturnForwardingAnalyzer
      def self.analyze(node, constructor_bindings:)
        new(constructor_bindings).analyze(node)
      end

      def initialize(constructor_bindings)
        @constructor_bindings = constructor_bindings
        @result = {} #: Hash[String, Set[Symbol]]
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
          readers = forwarded_readers(mbody)
          @result["#{class_name}##{mname}"] = readers unless readers.empty?
        end
      end

      # The readers of the returned proxy that map to the constructor's `self`
      # argument. Empty unless the method's return value is `K.new(args)` and K
      # has constructor-bound readers whose arg index holds `self`.
      def forwarded_readers(mbody)
        readers = Set.new #: Set[Symbol]
        ret = return_expr(mbody)
        return readers unless ret.is_a?(::Parser::AST::Node) && ret.type == :send

        recv, mname, *args = ret.children
        return readers unless mname == :new && recv
        klass = const_to_name(recv)
        return readers unless klass
        bindings = @constructor_bindings.bindings_for(klass)
        return readers unless bindings

        bindings.each do |reader, index|
          arg = args[index]
          readers << reader if arg.is_a?(::Parser::AST::Node) && arg.type == :self
        end
        readers
      end

      # The value a method body evaluates to: an explicit `return x`, else the
      # last statement.
      def return_expr(body)
        return nil unless body.is_a?(::Parser::AST::Node)
        node = body.type == :begin || body.type == :kwbegin ? body.children.last : body
        return nil unless node.is_a?(::Parser::AST::Node)
        node.type == :return ? node.children.first : node
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
