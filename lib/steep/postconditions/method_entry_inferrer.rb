module Steep
  module Postconditions
    # felixefelip/steep#68 item 4 + #78. Reads a method body as an ordered flow and recovers the
    # events the Runner turns into method-entry facts — recognized by STRUCTURE, not by the name
    # of the enclosing method.
    #
    # An event is `:call` (record the accumulated facts at the callee's entry), `:const_write`
    # (establish/invalidate the const the setter proves), or `:halt` (a `return if <pred>` guard
    # clause). Two flow shapes both fall out of this:
    #
    #   * A HALT-GATED flow — the generated controller runner, e.g.
    #
    #       def __rbs_infer__run_index
    #         authenticate_user       # guard G (proves facts on its non-halting exit)
    #         return if performed?    # :halt — past here, G did NOT halt, so G's facts hold
    #         index                   # M sees G's facts at entry
    #       end
    #
    #     G's facts are CONDITIONAL (gated on "didn't halt"); the `:halt` after G promotes them
    #     to unconditional for everything downstream. That promotion — not anything Rails- or
    #     controller-specific — is why the halt matters.
    #
    #   * A plain flow that writes a constant attribute, e.g.
    #
    #       def run
    #         Foo.name = 'x'          # establishes Foo.name
    #         Bar.new.foo_name        # <= Foo.name non-nil holds at foo_name's entry
    #         Foo.name = nil          # invalidates Foo.name
    #         Bar.new.foo_name_after  # <= nothing holds
    #       end
    #
    #     No `:halt`, so no guard facts are promoted — only the direct establishments carry.
    #
    # Owners are resolved from the typed call so an inherited/instance-receiver call resolves to
    # its definer. Under the project's whole-program (closed-world) assumption, intersecting a
    # method's entry facts over its observed call sites is treated as sound.
    class MethodEntryInferrer
      # One flow: `events` is an ordered list of `:call` / `:const_write` / `:halt` events,
      # and `owner` is the `"Class#method"` whose body this flow is (nil for a top-level
      # flow with no enclosing class). The Runner seeds a flow with `owner`'s own entry
      # facts before walking it, so facts propagate transitively through the call graph.
      RunnerSequence = Struct.new(:events, :owner, keyword_init: true)

      def self.sequences(source, typing)
        new(source, typing).sequences
      end

      # The `"Class#method"` keys of every method DEFINED in this source. An entry fact is only
      # useful for a method whose body gets re-type-checked from source, so the Runner keeps
      # facts only for these — dropping the dead facts a chain walk records for builtin/stdlib
      # calls (`String#upcase`, `Class#new`). Singleton defs normalize to `#` too, matching how
      # `record_entry_facts` keys everything.
      def self.defined_method_keys(source)
        new(source, nil).defined_method_keys
      end

      # `{ "Class#method" => [param name symbols] }` for every method defined in this source,
      # keyed the same way call owners resolve (`#` for both instance and singleton defs).
      # The Runner uses it to translate a call site's positional argument INDEX into the
      # callee's parameter NAME, so an argument-sensitive fact can be matched against the
      # `case <param>` subject on the consumer side.
      def self.method_param_names(source)
        new(source, nil).method_param_names
      end

      def initialize(source, typing)
        @source = source
        @typing = typing
      end

      def defined_method_keys
        keys = [] #: Array[String]
        walk_defs(@source.node, []) { |cls, mname| keys << "#{cls}##{mname}" } if @source.node
        # A top-level body checked with `@type self_method: Klass#method` IS the
        # source body of that method (an ERB template compiled to a method at
        # runtime), so it "defines" `Klass#method` for entry-fact purposes —
        # otherwise the Runner's defined-key filter drops the inferred fact.
        keys.concat(self_method_def_keys)
        keys
      end

      def method_param_names
        result = {} #: Hash[String, Array[Symbol]]
        return result unless @source.node
        walk_defs(@source.node, []) do |class_path, method_name, def_node|
          next unless def_node
          result["#{class_path}##{method_name}"] = positional_param_names(def_node)
        end
        result
      end

      # The leading required/optional positional parameter names of a def, in order. Stops at
      # the first rest/keyword/block parameter — past it a positional call-site index no
      # longer maps to a name.
      def positional_param_names(def_node)
        args = def_node.type == :defs ? def_node.children[2] : def_node.children[1]
        return [] unless args.is_a?(Parser::AST::Node)

        names = [] #: Array[Symbol]
        args.children.each do |param|
          break unless param.is_a?(Parser::AST::Node) && (param.type == :arg || param.type == :optarg)
          names << param.children[0]
        end
        names
      end

      # `["ERBPostsShow#__rbs_infer__body"]` for a source carrying
      # `@type self_method: ERBPostsShow#__rbs_infer__body`, else `[]`. The
      # annotation is parsed onto the root node at build time.
      def self_method_def_keys
        node = @source.node or return []
        (@source.mapping[node] || []).filter_map do |annot|
          next unless annot.is_a?(AST::Annotation::SelfMethod)
          type = annot.type
          next unless type.is_a?(AST::Types::Name::Instance)
          "#{type.name.to_s.sub(/\A::/, "")}##{annot.method_name}"
        end
      end

      def sequences
        return [] unless @source.node

        result = [] #: Array[RunnerSequence]
        each_method_def(@source.node, []) do |def_node, owner|
          events = method_events(def_node)
          # Keep a flow that either PRODUCES facts (`:halt` promotion / `:const_write`
          # establishment) OR merely PROPAGATES them (`:call`): once the Runner seeds a
          # flow with its owner's entry facts, a body of pure calls forwards those facts
          # to its callees (transitive narrowing). A body with none of these is inert.
          next if events.empty?
          result << RunnerSequence.new(events: events, owner: owner)
        end
        result
      end

      private

      # Yields `[def_node, "Class#method"]` for every method def under a class/module,
      # tracking lexical nesting for the owner key (nil at top level). Mirrors `walk_defs`
      # so owner keys line up with `defined_method_keys` and recorded callee keys.
      def each_method_def(node, nesting, &block)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class, :module
          name = const_lexical_name(node.children[0])
          inner = name ? nesting + [name] : nesting
          body = node.type == :class ? node.children[2] : node.children[1]
          each_method_def(body, inner, &block) if body
        when :def
          owner = nesting.empty? ? nil : "#{nesting.join("::")}##{node.children[0]}"
          yield node, owner
        when :begin, :kwbegin
          node.children.each { |c| each_method_def(c, nesting, &block) }
        when :sclass
          each_method_def(node.children[1], nesting, &block)
        else
          node.children.each { |c| each_method_def(c, nesting, &block) if c.is_a?(Parser::AST::Node) }
        end
      end

      # The ordered events of a method body, in source order. Each statement is a `Const.attr =
      # rhs` write (`:const_write`), a `return if <pred>` guard clause (`:halt`), or an
      # expression whose method calls are recovered in evaluation order
      # (`Bar.new.foo_name.upcase` => `new`, `foo_name`, `upcase`) so a callee whose entry we
      # care about isn't hidden as an inner receiver of a longer chain.
      def method_events(def_node)
        body = def_node.children[2]
        return [] unless body

        events = [] #: Array[Hash[Symbol, untyped]]
        statements(body).each do |stmt|
          if (cw = const_write_event(stmt))
            events << cw
          elsif halt_statement?(stmt)
            events << { kind: :halt }
          else
            call_targets(stmt).each do |target|
              each_call_send(target) do |send_node|
                next if send_node.children[1].to_s.end_with?("=")
                call = call_event(send_node) and events << call
              end
            end
          end
        end
        events
      end

      # A `return if <cond>` / `return unless <cond>` guard clause — the halt check that, in a
      # gated flow, promotes the preceding guard's conditional facts. Recognized purely by shape
      # (an `if` whose sole clause is a bare `return`), never by the predicate's name.
      def halt_statement?(stmt)
        return false unless stmt.is_a?(Parser::AST::Node) && stmt.type == :if

        _cond, then_clause, else_clause = stmt.children
        clause = then_clause || else_clause
        clause&.type == :return && (then_clause.nil? ^ else_clause.nil?)
      end

      # The sub-expressions whose calls we walk. A full `if/else` and a `case/when` are
      # BRANCH-SENSITIVE flows: we descend into EVERY branch, not just one. Each branch's
      # calls are dominated by the writes that precede the whole conditional (both branches
      # see them), so a call sitting in the `else` (`render :new` under `if @post.save`)
      # belongs in the flow exactly as much as one in the `then`. `@typing` already gives
      # each branch its branch-sensitive types, so no per-branch scoping is needed here —
      # only top-level statement writes are emitted as `:const_write`, so a write nested
      # inside one branch never leaks to a sibling branch or past the merge (conservative,
      # sound).
      #
      # A modifier conditional (`handler if cond` / `handler unless cond`) has a single
      # present clause; the `cond` is skipped. A bare expression is its own target. Halt
      # checks (`return if <pred>`) are handled separately, before this.
      def call_targets(stmt)
        case stmt.type
        when :if
          _cond, then_clause, else_clause = stmt.children
          [then_clause, else_clause].compact
        when :case
          _subject, *when_clauses, else_clause = stmt.children
          # A `when` node is `[*conditions, body]`; its body is the last child. The `case`
          # subject and each `when`'s conditions are skipped, like an `if`'s `cond`.
          bodies = when_clauses.map { |w| w.children.last }
          (bodies + [else_clause]).compact
        else
          [stmt]
        end
      end

      # Yields every `:send` node under `node` in evaluation order (a send's receiver and args
      # before the send itself), so chained calls are recorded in the order they run.
      def each_call_send(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        if node.type == :send
          receiver = node.children[0]
          each_call_send(receiver, &block) if receiver.is_a?(Parser::AST::Node)
          node.children.drop(2).each { |a| each_call_send(a, &block) if a.is_a?(Parser::AST::Node) }
          yield node
        else
          node.children.each { |c| each_call_send(c, &block) if c.is_a?(Parser::AST::Node) }
        end
      end

      # `Const.attr = <rhs>` => `{ kind: :const_write, base:, attr:, nonnil: }`, else nil. The
      # receiver must be a constant (self/ivar writes are items 1/2's job).
      def const_write_event(stmt)
        return nil unless stmt.is_a?(Parser::AST::Node) && stmt.type == :send

        receiver, mname, *args = stmt.children
        return nil unless mname.to_s.end_with?("=") && mname != :==
        return nil unless receiver.is_a?(Parser::AST::Node) && receiver.type == :const

        base = const_receiver_name(receiver) or return nil
        rhs = args.last
        return nil unless rhs.is_a?(Parser::AST::Node)

        { kind: :const_write, base: base, attr: mname.to_s.chomp("="), nonnil: nonnil_rhs?(rhs) }
      end

      # A resolved method call => `{ kind: :call, class_name:, method_name:, same_self:,
      # arg_keys: }`, else nil. `same_self` is false for an explicit non-self receiver — a
      # cross-object call (`Bar.new.foo_name`) carries only const (global) facts, never the
      # caller's `self`-method facts. `arg_keys` records the LEADING positional literal
      # arguments as `[index, LiteralKey]` pairs (`show(:name)` => `[[0, ":name"]]`), which
      # the Runner turns into argument-sensitive entry facts.
      def call_event(send_node)
        owner = resolve_owner(send_node) or return nil
        receiver = send_node.children[0]
        same_self = receiver.nil? || (receiver.is_a?(Parser::AST::Node) && receiver.type == :self)

        {
          kind: :call,
          class_name: owner[:class_name],
          method_name: owner[:method_name],
          same_self: same_self,
          arg_keys: literal_arg_keys(send_node)
        }
      end

      # The leading positional literal arguments of a call, as `[index, LiteralKey]` pairs.
      # Stops at the first non-literal / splat / keyword / block argument — past it the
      # positional indices are no longer reliable.
      def literal_arg_keys(send_node)
        keys = [] #: Array[[Integer, String]]
        send_node.children.drop(2).each_with_index do |arg, index|
          key = LiteralKey.of(arg) or break
          keys << [index, key]
        end
        keys
      end

      def resolve_owner(call_node)
        call = @typing.call_of(node: call_node) rescue (return nil)
        return nil unless call.is_a?(TypeInference::MethodCall::Typed)

        decl = call.method_decls.find { |d| d.method_name.respond_to?(:type_name) }
        return nil unless decl

        {
          class_name: decl.method_name.type_name.to_s.sub(/\A::/, ""),
          method_name: call_node.children[1]
        }
      end

      # The full resolved name of a constant receiver (`Foo` inside `Example4` => `Example4::Foo`),
      # read off its singleton type so it keys the setter entry / entry-fact map by identity — the
      # same resolution `TypeConstruction#resolved_const_name_string` uses on the read side. Falls
      # back to the lexical path when the type is unavailable.
      def const_receiver_name(receiver)
        type = (@typing.type_of(node: receiver) rescue nil)
        if type.is_a?(AST::Types::Name::Singleton)
          return type.name.to_s.sub(/\A::/, "")
        end
        const_lexical_name(receiver)
      end

      def const_lexical_name(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :const
        parent, name = node.children
        parent ? "#{const_lexical_name(parent)}::#{name}" : name.to_s
      end

      # Whether a written value is provably non-nil (so the const can be asserted present). A
      # nilable or untyped RHS => false: nothing is established, and it invalidates instead.
      def nonnil_rhs?(rhs)
        type = (@typing.type_of(node: rhs) rescue nil)
        return false unless type
        return false if type.is_a?(AST::Types::Any) || type.is_a?(AST::Types::Nil)
        if type.is_a?(AST::Types::Union)
          return type.types.none? { |t| t.is_a?(AST::Types::Nil) || t.is_a?(AST::Types::Any) }
        end
        true
      end

      def statements(body)
        body.type == :begin ? body.children : [body]
      end

      # Yields `(class_name, method_name)` for every `def`/`def self.` under a class/module.
      def walk_defs(node, nesting, &block)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class, :module
          name = const_lexical_name(node.children[0])
          inner = name ? nesting + [name] : nesting
          body = node.type == :class ? node.children[2] : node.children[1]
          walk_defs(body, inner, &block) if body
        when :def
          yield nesting.join("::"), node.children[0], node unless nesting.empty?
        when :defs
          yield nesting.join("::"), node.children[1], node unless nesting.empty?
        when :begin, :kwbegin
          node.children.each { |c| walk_defs(c, nesting, &block) }
        when :sclass
          walk_defs(node.children[1], nesting, &block)
        else
          node.children.each { |c| walk_defs(c, nesting, &block) if c.is_a?(Parser::AST::Node) }
        end
      end
    end
  end
end
