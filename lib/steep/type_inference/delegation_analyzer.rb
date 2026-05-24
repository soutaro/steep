module Steep
  module TypeInference
    # Walks a parsed Ruby AST and identifies methods whose body is
    # exactly a forward delegation — `def m(args); receiver.m(args); end`,
    # endless `def m(args) = receiver.m(args)`, or arg-forwarding
    # variant. The output is consumed by `TypeConstruction#type_send`
    # to inline calls to forward-delegating methods so that narrowing
    # applied to the equivalent expanded expression (`host.receiver.m`)
    # also covers the original call site (`host.m`).
    #
    # Detection is purely syntactic: only methods whose body is *exactly*
    # one of the recognized forward shapes qualify. Bodies that compute
    # or transform (`def m; do_something; receiver.m; end`,
    # `def m; receiver.m.to_s; end`) intentionally don't match — the
    # narrowing/inlining assumption only holds for true forwards.
    #
    # felixefelip/steep#32.
    class DelegationAnalyzer
      # A method whose body inlines to `host.<receiver>.<delegate_method>(args)`.
      # Both same-name (`def m; receiver.m; end`) and renaming
      # (`def venue_name; venue.name; end`) forwards qualify — the
      # only requirement is that the body is a single send whose
      # receiver is a known attr-shape (ivar or implicit-self send).
      #
      # Fields:
      #   :receiver_kind   — `:attr_send` (`def m; foo.x; end`) or
      #                      `:ivar` (`def m; @foo.x; end`).
      #   :receiver_name   — `Symbol`, the attr method name (`:foo`)
      #                      or ivar name including `@` (`:@foo`).
      #   :delegate_method — `Symbol`, the method invoked on the
      #                      receiver (`:name`, `:venue_name`, etc.).
      DelegationInfo = Struct.new(:receiver_kind, :receiver_name, :delegate_method, keyword_init: true)

      def self.analyze(node)
        new.analyze(node)
      end

      def initialize
        @result = {} #: Hash[String, Hash[Symbol, DelegationInfo]]
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
          walk(body, nesting: new_nesting) if body
        when :module
          const_node, body = node.children
          name = const_to_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk(body, nesting: new_nesting) if body
        when :def
          register_if_delegate(node, nesting: nesting)
        when :defs
          # Singleton method bodies don't get delegation analysis —
          # the narrowing patterns we serve are instance-level.
        when :begin, :kwbegin
          node.children.each { |c| walk(c, nesting: nesting) if c.is_a?(::Parser::AST::Node) }
        else
          node.children.each { |c| walk(c, nesting: nesting) if c.is_a?(::Parser::AST::Node) }
        end
      end

      def register_if_delegate(def_node, nesting:)
        return if nesting.empty?
        method_name = def_node.children[0]
        body = def_node.children[2]
        return unless body

        info = detect_forward_delegation(body, method_name: method_name)
        return unless info

        class_name = nesting_to_class_name(nesting)
        @result[class_name] ||= {}
        @result[class_name][method_name] = info
      end

      # Recognizes the body shape `receiver.delegate_method(args)` where:
      # - receiver is `:ivar` (`@foo`) or `:send` with nil receiver
      #   (an implicit-self call to `foo` — a likely attr_reader; the
      #   actual attr_reader check happens at apply time against the
      #   receiver's RBS def)
      # - args are either empty or all forwarded shapes (splat,
      #   kwsplat, lvar/ivar). The actual arg compatibility is
      #   delegated to Steep's own type-send checking at apply time.
      #
      # Same-name forwards (`def m; receiver.m; end`) and renaming
      # forwards (`def venue_name; venue.name; end`) both qualify —
      # the narrowing semantic is the same: typing `host.<method>`
      # is equivalent to typing `host.<receiver>.<delegate_method>`,
      # so receivers narrowed in the caller env propagate through.
      def detect_forward_delegation(body, method_name:)
        return nil unless body.is_a?(::Parser::AST::Node)
        return nil unless body.type == :send
        send_receiver, send_method, *send_args = body.children
        return nil unless empty_or_simple_forward?(send_args)

        case send_receiver&.type
        when :ivar
          ivar_name = send_receiver.children[0]
          DelegationInfo.new(receiver_kind: :ivar, receiver_name: ivar_name, delegate_method: send_method)
        when :send
          recv2, name2, *args2 = send_receiver.children
          return nil unless recv2.nil? && args2.empty?
          DelegationInfo.new(receiver_kind: :attr_send, receiver_name: name2, delegate_method: send_method)
        end
      end

      def empty_or_simple_forward?(args)
        return true if args.empty?
        # `def m(*a); receiver.m(*a); end` — single splat forwarding.
        # More general arg-forwarding (`*a, **kw, &blk`) is also accepted
        # — the actual arg compatibility is delegated to Steep's own
        # method-call type checking at apply time.
        args.all? do |a|
          next true unless a.is_a?(::Parser::AST::Node)
          [:splat, :kwsplat, :block_pass, :forward_arg, :forwarded_args, :lvar, :ivar, :kwargs, :hash].include?(a.type)
        end
      end

      def nesting_to_class_name(nesting)
        nesting.join("::").sub(/\A::/, "")
      end

      # `(:const nil :Foo)` → `"Foo"`,
      # `(:const (:const nil :Foo) :Bar)` → `"Foo::Bar"`,
      # `(:const (:cbase) :Top)` → `"Top"` (cbase drops; we work with
      # logical class names rather than absolute references).
      def const_to_name(node)
        return nil unless node.is_a?(::Parser::AST::Node)
        case node.type
        when :const
          parent, name = node.children
          parent_name = parent ? const_to_name(parent) : nil
          parent_name ? "#{parent_name}::#{name}" : name.to_s
        when :cbase
          nil
        end
      end
    end
  end
end
