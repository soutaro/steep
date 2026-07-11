module Steep
  module TypeInference
    # Walks a parsed Ruby AST and, for each class, maps an attr-style reader
    # method to the *positional constructor parameter* its backing ivar is
    # assigned from:
    #
    #   class Proxy
    #     def initialize(klass, owner); @owner = owner; end
    #     def owner; @owner; end
    #   end
    #   # => { "Proxy" => { owner: 1 } }
    #
    # Consumed by `TypeConstruction` at `.new` call sites to translate an
    # `initialize` precondition on `self.<reader>...` into an obligation on the
    # matching constructor argument (felixefelip/steep#60): given
    # `Proxy#initialize requires not_nil self.owner.user`, a call
    # `Proxy.new(klass, self)` implies `not_nil self.user` on the enclosing
    # method, because `@owner` is bound to argument index 1 (`self`).
    #
    # Detection is purely syntactic and conservative: a reader qualifies only
    # when its body is exactly `@ivar`, and that ivar is assigned in
    # `initialize` exactly from a plain positional parameter (`arg`/`optarg`).
    # Anything else (computed reader, splat/kwarg params, conditional
    # assignment) is skipped — the translation is only sound for a direct bind.
    class ConstructorBindingAnalyzer
      def self.analyze(node)
        new.analyze(node)
      end

      def initialize
        @result = {} #: Hash[String, Hash[Symbol, Integer]]
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
          register_class(body, nesting: new_nesting) if body && name
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

      # Collect `@ivar => param_index` from `initialize` and `reader => @ivar`
      # from single-ivar reader defs at this class level, then compose the two
      # into `reader => param_index` entries.
      def register_class(body, nesting:)
        ivar_to_param = {} #: Hash[Symbol, Integer]
        reader_to_ivar = {} #: Hash[Symbol, Symbol]

        each_stmt(body) do |stmt|
          next unless stmt.type == :def
          mname, args, mbody = stmt.children
          if mname == :initialize
            ivar_to_param.merge!(ivar_param_bindings(args, mbody))
          elsif (ivar = single_ivar_reader(mbody))
            reader_to_ivar[mname] = ivar
          end
        end

        entries = {} #: Hash[Symbol, Integer]
        reader_to_ivar.each do |reader, ivar|
          idx = ivar_to_param[ivar]
          entries[reader] = idx if idx
        end
        return if entries.empty?

        key = nesting.join("::")
        (@result[key] ||= {}).merge!(entries)
      end

      # `@x = param` bindings in `initialize`, keyed by ivar, valued by the
      # positional index of `param` in the constructor's parameter list.
      def ivar_param_bindings(args_node, body)
        return {} unless args_node.is_a?(::Parser::AST::Node)

        param_index = {} #: Hash[Symbol, Integer]
        args_node.children.each_with_index do |arg, i|
          next unless arg.is_a?(::Parser::AST::Node)
          # Only plain positional params keep a stable index the call site can
          # match against; a splat/kwarg/block shifts or breaks positionality.
          param_index[arg.children[0]] = i if arg.type == :arg || arg.type == :optarg
        end
        return {} if param_index.empty?

        result = {} #: Hash[Symbol, Integer]
        each_stmt(body) do |stmt|
          next unless stmt.type == :ivasgn
          ivar, rhs = stmt.children
          next unless rhs.is_a?(::Parser::AST::Node) && rhs.type == :lvar
          idx = param_index[rhs.children[0]]
          result[ivar] = idx if idx
        end
        result
      end

      # A reader whose body is exactly `@ivar` (normal or endless def) →
      # returns `:@ivar`, else nil.
      def single_ivar_reader(body)
        return nil unless body.is_a?(::Parser::AST::Node)
        body.type == :ivar ? body.children[0] : nil
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
