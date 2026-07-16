module Steep
  module Postconditions
    # Walks the typed AST of a Ruby source and proposes
    # `unconditional.ivars` postcondition entries for methods that assign
    # an instance variable to a type strictly narrower than the variable's
    # RBS declaration.
    #
    # Symmetric to `Steep::Contracts::Inferrer` (preconditions). Where
    # the contracts inferrer reads diagnostic output to surface required
    # callsite checks, the postcondition inferrer reads the method body
    # itself and surfaces side effects that refine the caller's view.
    #
    # MVP heuristic:
    #
    #   - Walk every `:def` inside a class/module body.
    #   - For each def, collect all `:ivasgn` nodes in the body. If an
    #     ivar is assigned more than once, the LAST write wins (linear
    #     flow assumption; conditional assigns are handled conservatively
    #     by relying on Steep's own type at the assignment node).
    #   - For each ivar, look up the *declared* type in the class's RBS
    #     definition. If the RHS type is a strict subtype, emit the
    #     refinement.
    #   - Methods whose def is inside a singleton (`def self.x`) emit a
    #     singleton entry; everything else is an instance entry.
    class Inferrer
      include TypedNodeUtils

      def self.infer(source, typing, subtyping)
        new(source, typing, subtyping).infer
      end

      def initialize(source, typing, subtyping)
        @source = source
        @typing = typing
        @subtyping = subtyping
        @factory = subtyping.factory
        @definition_builder = subtyping.factory.definition_builder
        @return_establishment_inferrer = ReturnEstablishmentInferrer.new(typing, subtyping)
      end

      def infer
        return [] unless @source.node

        results = []
        walk_classes(@source.node, nesting: []) do |def_node, class_name, singleton|
          ivars = collect_ivar_refinements(def_node, class_name, singleton: singleton)
          when_true_ivars = collect_when_true_nonnil_refinements(def_node, class_name, singleton: singleton)
          returns_establishes = @return_establishment_inferrer.establishments(def_node)
          may_write = collect_ivar_writes(def_node, class_name, singleton: singleton)
          self_call_deps = collect_self_call_deps(def_node)
          returns_ivar = collect_returns_ivar(def_node, class_name, singleton: singleton)
          conditional_returns = collect_conditional_returns(def_node, class_name, singleton: singleton)
          conditional_const_returns = collect_conditional_const_returns(def_node)
          establishes_consts = collect_establishes_consts(def_node, singleton: singleton)
          delegates_to_instance = singleton_delegates_to_instance?(def_node, singleton: singleton)
          if ivars.empty? && when_true_ivars.empty? && returns_establishes.empty? &&
             may_write.empty? && self_call_deps.empty? && returns_ivar.nil? &&
             conditional_returns.empty? && conditional_const_returns.empty? &&
             establishes_consts.empty? && !delegates_to_instance
            next
          end

          method_name = def_node.children[0]
          self_type_string = marker_self_type_for(class_name, method_name, singleton: singleton) unless ivars.empty?
          when_true_self_type_string = marker_self_type_for(class_name, method_name, singleton: singleton) unless when_true_ivars.empty?

          results << InferredEntry.new(
            class_name: class_name,
            method_name: method_name,
            singleton: singleton,
            ivars: ivars,
            self_type_string: self_type_string,
            when_true_ivars: when_true_ivars,
            when_true_self_type_string: when_true_self_type_string,
            returns_establishes: returns_establishes,
            may_write_ivars: may_write,
            self_call_deps: self_call_deps,
            returns_ivar: returns_ivar,
            conditional_returns: conditional_returns,
            conditional_const_returns: conditional_const_returns,
            establishes_consts: establishes_consts,
            delegates_to_instance: delegates_to_instance
          )
        end
        results
      end

      private

      # Composes the `unconditional.self:` value for an inferred entry,
      # following the `MarkerNaming` convention shared with rbs_infer.
      # Instance methods get `"::ClassName & ::ClassName::AfterMethod"`
      # so consumers (`apply_unconditional_postconditions`) can REPLACE
      # the receiver's type with the intersection. Singleton methods
      # don't get a marker — there's no established convention for
      # narrowing a class/module value, and the inferrer for those is
      # rare in practice. Method names that strip to empty under
      # `pascal_case` (e.g. `:"="`) are also skipped.
      def marker_self_type_for(class_name, method_name, singleton:)
        return nil if singleton
        return nil unless MarkerNaming.valid_method_name?(method_name)
        MarkerNaming.narrowed_self_type_for(class_name, method_name)
      end

      # Walks the AST yielding (def_node, class_name, singleton?) for each
      # method definition found inside a class/module. Skips top-level
      # `def`s (no class to attach a postcondition to).
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
          yield node, nesting.join("::"), false unless nesting.empty?
        when :defs
          receiver, _name, _args, _body = node.children
          if receiver&.type == :self && !nesting.empty?
            # Reshape `(:defs (self) name args body)` as `(:def name args body)`
            # so downstream code can read children[0] uniformly.
            shaped = node.updated(:def, node.children.drop(1))
            yield shaped, nesting.join("::"), true
          end
        when :begin, :kwbegin
          node.children.each { |child| walk_classes(child, nesting: nesting, &block) }
        when :sclass
          # `class << self`: the body's `def x` is a singleton method on
          # the surrounding constant. Recurse with a flag.
          body = node.children[1]
          walk_singleton_body(body, nesting: nesting, &block) if body
        else
          node.children.each do |child|
            walk_classes(child, nesting: nesting, &block) if child.is_a?(Parser::AST::Node)
          end
        end
      end

      def walk_singleton_body(node, nesting:, &block)
        return unless node.is_a?(Parser::AST::Node)
        case node.type
        when :def
          yield node, nesting.join("::"), true unless nesting.empty?
        when :begin, :kwbegin
          node.children.each { |child| walk_singleton_body(child, nesting: nesting, &block) }
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

      # Returns `Hash[Symbol, AST::Types::t]` of `@ivar` to refined type,
      # populated only for ivars whose RHS type at the last assignment in
      # the body is a strict subtype of their RBS declaration.
      def collect_ivar_refinements(def_node, class_name, singleton:)
        body = def_node.children[2]
        return {} unless body

        last_writes = {} #: Hash[Symbol, AST::Types::t]
        walk_ivasgns(body) do |ivasgn_node|
          name = ivasgn_node.children[0]
          rhs_node = ivasgn_node.children[1]
          next unless rhs_node
          rhs_type = intrinsic_type_of(rhs_node)
          next unless rhs_type
          last_writes[name] = rhs_type
        end
        return {} if last_writes.empty?

        declared_types = declared_ivar_types(class_name, singleton: singleton)
        last_writes.each_with_object({}) do |(name, rhs_type), result|
          declared = declared_types[name]
          next unless declared
          next unless strict_subtype?(rhs_type, declared)
          result[name] = rhs_type
        end
      end

      # Returns `Hash[Symbol, AST::Types::t]` mapping `@ivar` to its
      # refined type for methods whose body, when evaluated by the
      # `LogicTypeInterpreter`, narrows one or more ivars in the
      # truthy branch.
      #
      # Defers all shape recognition to the same logical-type
      # machinery Steep uses for `if`/`unless`/`&&`/`||` narrowing —
      # so `!@x.nil?`, `@x.is_a?(Klass)` and any future Logic-type
      # patterns are picked up uniformly, without re-implementing
      # the case analysis here.
      #
      # The interpreter runs against a fresh env populated only with
      # the class's declared instance variables; the result's truthy
      # env is compared to that baseline. Ivar entries that ended up
      # strictly narrower (declared `T?` → refined `T`) become
      # postcondition refinements. Equal entries are dropped — a
      # no-op refinement would only add sidecar noise.
      def collect_when_true_nonnil_refinements(def_node, class_name, singleton:)
        body = def_node.children[2]
        return {} unless body
        last_expr = last_expression(body) or return {}

        return {} unless predicate_body?(last_expr)

        env = build_env_for_class(class_name, singleton: singleton) or return {}
        interpreter = build_interpreter_for_class(class_name, singleton: singleton)
        return {} unless interpreter

        truthy_result = nil
        begin
          truthy_result = evaluate_truthy(interpreter: interpreter, env: env, node: last_expr)
        rescue StandardError => e
          Steep.logger.warn { "[postconditions] when_true inference failed for #{class_name}##{def_node.children[0]}: #{e.message}" }
          return {}
        end
        return {} unless truthy_result
        return {} if truthy_result.unreachable

        declared = declared_ivar_types(class_name, singleton: singleton)
        refined_ivars = truthy_result.env.instance_variable_types
        refined_ivars.each_with_object({}) do |(name, refined_type), result|
          declared_type = declared[name]
          next unless declared_type
          next if refined_type == declared_type
          next unless strict_subtype?(refined_type, declared_type)
          result[name] = refined_type
        end
      end

      # Returns the LogicTypeInterpreter `Result` for the truthy
      # branch of `node`, handling `:and`/`:or` by composition.
      # The interpreter natively dispatches on `:send` /
      # `Logic::Env`-typed nodes, but method bodies aren't
      # type-checked in conditional mode, so `:and`/`:or` nodes
      # carry plain Boolean types and the interpreter's default
      # path would refine nothing. Walking them here threads the
      # truthy env from the left side into the right side's
      # evaluation, matching what `type_construction.rb`'s `:and`
      # handler does during real conditional type-checking.
      def evaluate_truthy(interpreter:, env:, node:)
        case node.type
        when :and
          left_truthy = evaluate_truthy(interpreter: interpreter, env: env, node: node.children[0])
          return nil unless left_truthy
          return left_truthy if left_truthy.unreachable
          evaluate_truthy(interpreter: interpreter, env: left_truthy.env, node: node.children[1])
        else
          truthy_result, _falsy_result = interpreter.eval(env: env, node: node)
          truthy_result
        end
      end

      # Whether `node` is or recursively contains a logic-typed
      # sub-expression (`Logic::Base` / `Logic::Env`) the interpreter
      # can derive a narrowing from. Method bodies aren't
      # type-checked in conditional mode, so `:and`/`:or` operators
      # carry plain Boolean — recursing into their operands is the
      # only way to spot a nil-check buried inside `a && b`.
      def predicate_body?(node)
        case node&.type
        when :and, :or
          predicate_body?(node.children[0]) || predicate_body?(node.children[1])
        else
          type = type_of(node)
          return false unless type
          type.is_a?(AST::Types::Logic::Base) || type.is_a?(AST::Types::Logic::Env)
        end
      end

      # Minimal env with just the class's declared instance variables
      # populated, scoped to a fresh `ConstantEnv`. The interpreter
      # mutates the env on refinement; we compare the result against
      # the same baseline to surface only the differences.
      def build_env_for_class(class_name, singleton:)
        ivars = declared_ivar_types(class_name, singleton: singleton)
        return nil if ivars.empty?

        const_env = TypeInference::ConstantEnv.new(
          factory: @factory,
          context: nil,
          resolver: RBS::Resolver::ConstantResolver.new(builder: @factory.definition_builder)
        )
        env = TypeInference::TypeEnv.new(const_env)
        env.refine_types(instance_variable_types: ivars)
      end

      def build_interpreter_for_class(class_name, singleton:)
        type_name = RBS::TypeName.parse("::#{class_name}").absolute! rescue nil
        return nil unless type_name

        instance_type =
          if singleton
            AST::Types::Name::Singleton.new(name: type_name)
          else
            AST::Types::Name::Instance.new(name: type_name, args: [])
          end
        class_type = AST::Types::Name::Singleton.new(name: type_name)

        config = Interface::Builder::Config.new(
          self_type: instance_type,
          class_type: class_type,
          instance_type: instance_type,
          variable_bounds: {}
        )

        TypeInference::LogicTypeInterpreter.new(
          subtyping: @subtyping,
          typing: @typing,
          config: config,
          self_type: instance_type
        )
      end

      # felixefelip/steep#68 (item 1), the EFFECT side of the inference.
      #
      # Every declared ivar the body assigns — anywhere, including inside a
      # block it passes to someone else (`respond_to { |f| f.html { @x = 1 } }`),
      # since a block body runs in this same `self`. Unlike
      # `collect_ivar_refinements` this records no type: it is a MAY-write, used
      # by the caller only to drop a now-stale narrowing.
      def collect_ivar_writes(def_node, class_name, singleton:)
        body = def_node.children[2]
        return Set[] unless body

        declared = declared_ivar_types(class_name, singleton: singleton)
        writes = Set.new #: Set[Symbol]
        walk_ivasgns(body) do |ivasgn_node|
          name = ivasgn_node.children[0]
          writes << name if declared.key?(name)
        end
        writes
      end

      # The self-sends of the body, as `"Class#method"` keys — the edges of the
      # call graph the Runner closes over, so that a method whose only "write" is
      # a call to something that writes (`authenticate_user` -> `redirect_to`)
      # still reports the effect.
      #
      # Only self-sends: an ivar write inside `other.foo` mutates OTHER's ivars,
      # not ours. The callee's OWNER comes from the typed call (`method_decls`),
      # so an inherited method resolves to the class that declares it
      # (`redirect_to` -> `ActionController::Base`), which is how the store is
      # keyed.
      def collect_self_call_deps(def_node)
        body = def_node.children[2]
        return Set[] unless body

        deps = Set.new #: Set[String]
        walk_sends(body) do |send_node|
          receiver = send_node.children[0]
          next unless receiver.nil? || receiver.type == :self

          call = @typing.call_of(node: send_node) rescue nil
          next unless call.is_a?(TypeInference::MethodCall::Typed)

          call.method_decls.each do |decl|
            method_name = decl.method_name
            next unless method_name.respond_to?(:type_name)

            owner = method_name.type_name.to_s.sub(/\A::/, "")
            deps << "#{owner}##{method_name.method_name}"
          end
        end
        deps
      end

      # felixefelip/steep#68 (item 2), the halt-check link. A method whose body
      # is a single instance-variable read (`def performed?; @halted; end`) is a
      # transparent getter of that ivar: testing it (`return if performed?`) must
      # narrow the ivar, just as `attr_reader` already does. Returns the ivar
      # name or nil.
      def collect_returns_ivar(def_node, class_name, singleton:)
        body = def_node.children[2]
        return nil unless body

        expr = last_expression(body)
        return nil unless expr&.type == :ivar

        name = expr.children[0]
        declared_ivar_types(class_name, singleton: singleton).key?(name) ? name : nil
      end

      # felixefelip/steep#68 (item 2), the positive proof. Recognises a guard
      # clause that aborts unless a nilable self-method is present:
      #
      #   def authenticate_user
      #     unless current_user      # `if !current_user` too
      #       redirect_to root_path  # writes a may-write ivar => halts
      #       return
      #     end
      #     ...
      #   end
      #
      # On the exit that did NOT halt, `current_user` is proven non-nil. That
      # fact is gated by the ivar the halting branch writes (`@halted`): a caller
      # sees it only where that ivar is known falsy — which is exactly what
      # `return if performed?` establishes (via `returns_ivar`).
      #
      # => Hash[Symbol(method), { gate_ivar: Symbol?, gate_via: Symbol?, type: }]
      # The gate is expressed as either the ivar the abort clause writes directly
      # (`gate_ivar`) OR the self-method it calls to halt (`gate_via`, e.g.
      # `redirect_to`) — the Runner resolves `gate_via` to the ivar that method
      # actually writes, once the may-write closure is known.
      def collect_conditional_returns(def_node, class_name, singleton:)
        body = def_node.children[2]
        return {} unless body

        result = {} #: Hash[Symbol, untyped]
        each_statement(body) do |stmt|
          guard = negative_presence_guard(stmt) or next
          method, gate = guard
          next if result.key?(method)

          nonnil = nonnil_return_of_self_method(method, class_name, singleton: singleton) or next
          result[method] = gate.merge(type: nonnil)
        end
        result
      end

      # felixefelip/steep#68 (item 3) — the constant-rooted proof. A guard that
      # halts, then writes a non-nil value to a constant attribute:
      #
      #   def authenticate_user
      #     unless current_user
      #       redirect_to        # halts => gate @performed
      #       return
      #     end
      #     Current.user = current_user   # top-level, non-nil (past the guard)
      #   end
      #
      # proves `Current.user` non-nil on the unhalted exit, gated by the same
      # halt ivar as the self-method case. Keyed by the `"Const.attr"` path.
      #
      # => Hash[String, { gate_ivar: Symbol?, gate_via: Symbol?, type: }]
      def collect_conditional_const_returns(def_node)
        body = def_node.children[2]
        return {} unless body

        gate = method_halt_gate(body) or return {}

        result = {} #: Hash[String, untyped]
        each_statement(body) do |stmt|
          write = const_attr_write(stmt) or next
          const_path, rhs = write
          next if result.key?(const_path)

          type = nonnil_value_type(rhs) or next
          result[const_path] = gate.merge(type: type)
        end
        result
      end

      # felixefelip/steep#68 item 5, the establishment side. For an INSTANCE
      # setter (`def user=(value)`), the other constant attributes its body
      # establishes non-nil, given its argument is non-nil:
      #
      #   def user=(value)
      #     super(value)
      #     self.author_name = value&.full_name   # => establishes author_name
      #   end
      #
      # `value&.full_name` is non-nil when `value` is (the safe-nav's only nil
      # source), so setting `user` to a non-nil value sets `author_name` too.
      # Keyed by attribute name; the Runner promotes these to the constant
      # (`Current.author_name`) at each `Current.user = <non-nil>` write site.
      # => Hash[Symbol(attr), AST::Types::t]
      def collect_establishes_consts(def_node, singleton:)
        return {} if singleton
        return {} unless def_node.children[0].to_s.end_with?("=") && def_node.children[0] != :==

        param = setter_param_name(def_node) or return {}
        body = def_node.children[2] or return {}

        result = {} #: Hash[Symbol, untyped]
        walk_nodes(body) do |n|
          write = self_attr_write(n) or next
          attr, rhs = write
          type = param_guarded_nonnil_type(rhs, param) or next
          result[attr] = type
        end
        result
      end

      # Whether a SINGLETON setter (`def self.user=(value)`) delegates to the
      # instance one (`instance.user = value`) — the CurrentAttributes shape the
      # rbs_infer generator emits. Only then is it sound to attribute the
      # instance setter's establishments to a `Const.user =` write.
      def singleton_delegates_to_instance?(def_node, singleton:)
        return false unless singleton
        attr = def_node.children[0].to_s
        return false unless attr.end_with?("=")
        body = def_node.children[2] or return false

        found = false
        walk_nodes(body) do |n|
          next unless n.type == :send && n.children[1].to_s == attr
          recv = n.children[0]
          found = true if recv&.type == :send && recv.children[0].nil? && recv.children[1] == :instance
        end
        found
      end

      def setter_param_name(def_node)
        args = def_node.children[1]
        req = args&.children&.find { |a| a.is_a?(Parser::AST::Node) && a.type == :arg }
        req&.children&.first
      end

      # `self.<attr> = <rhs>` => `[attr_sym, rhs_node]`, else nil.
      def self_attr_write(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :send

        method = node.children[1].to_s
        return nil unless method.end_with?("=") && node.children[1] != :==

        receiver = node.children[0]
        return nil unless receiver.is_a?(Parser::AST::Node) && receiver.type == :self

        rhs = node.children[2] or return nil
        [method.chomp("=").to_sym, rhs]
      end

      # For `<param>&.<method>` / `<param>.<method>`, the method's return on the
      # param's NON-NIL type, when that return is itself non-nil (so the write
      # establishes the attribute). nil otherwise.
      def param_guarded_nonnil_type(rhs, param)
        return nil unless rhs.is_a?(Parser::AST::Node) && (rhs.type == :send || rhs.type == :csend)

        recv = rhs.children[0]
        return nil unless recv.is_a?(Parser::AST::Node) && recv.type == :lvar && recv.children[0] == param

        recv_type = type_of(recv) or return nil
        ret = resolve_method_return(subtract_nil(recv_type), rhs.children[1]) or return nil
        subtract_nil(ret) == ret ? ret : nil
      end

      # The return type of `method` resolved on `type` (walking union/
      # intersection members), or nil.
      def resolve_method_return(type, method)
        instance_type_names(type).each do |type_name|
          definition = @definition_builder.build_instance(type_name) rescue next
          method_def = definition.methods[method] or next
          types = method_def.method_types.map { |mt| @factory.type(mt.type.return_type) }
          next if types.empty?

          return types.size == 1 ? types.first : AST::Types::Union.build(types: types)
        end
        nil
      end

      def instance_type_names(type)
        case type
        when AST::Types::Name::Instance
          [type.name]
        when AST::Types::Intersection, AST::Types::Union
          type.types.flat_map { |t| instance_type_names(t) }
        else
          []
        end
      end

      # The halt gate of a method: the gate of the first top-level guard-clause
      # that halts and returns. Independent of what the clause's condition tests
      # — item 3's write isn't in the clause, it just shares the exit gate.
      def method_halt_gate(body)
        each_statement(body) do |stmt|
          next unless stmt.is_a?(Parser::AST::Node) && stmt.type == :if

          _, true_clause, false_clause = stmt.children
          abort_clause = true_clause || false_clause
          next unless abort_clause && (true_clause.nil? ^ false_clause.nil?)
          next unless clause_returns?(abort_clause)

          gate = halting_gate(abort_clause) and return gate
        end
        nil
      end

      # `Current.user = <rhs>` => `["Current.user", rhs_node]`, else nil. The
      # receiver must be a constant (self/ivar writes are items 1/2's job).
      def const_attr_write(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :send

        method = node.children[1]
        return nil unless method.to_s.end_with?("=") && method != :==

        receiver = node.children[0]
        return nil unless receiver.is_a?(Parser::AST::Node) && receiver.type == :const

        const_name = extract_const_name(receiver) or return nil
        rhs = node.children[2] or return nil

        ["#{const_name}.#{method.to_s.chomp("=")}", rhs]
      end

      # The type of a written value, only when it is provably non-nil at that
      # point (so `Current.user` can be asserted present). A nilable or untyped
      # RHS yields nil — nothing is proven.
      def nonnil_value_type(rhs)
        type = type_of(rhs) or return nil
        return nil if type.is_a?(AST::Types::Any)
        return nil unless subtract_nil(type) == type # already nil-free

        type
      end

      # Matches `unless <self.method>; <halts>; return; end` (or the
      # `if !<self.method>` spelling) and returns `[method, gate]`, where `gate`
      # is `{ gate_ivar: }` or `{ gate_via: }`. The aborting branch must both
      # halt (write an ivar directly, or call a self-method that does) and
      # `return`.
      def negative_presence_guard(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :if

        cond, true_clause, false_clause = node.children
        # `unless X` parses as `if X (nil-then) (else)`, so the aborting body is
        # whichever clause exists; require exactly one, guarded on the bare cond.
        method = presence_condition_method(cond) or return nil
        abort_clause = true_clause || false_clause
        return nil unless abort_clause && (true_clause.nil? ^ false_clause.nil?)
        return nil unless clause_returns?(abort_clause)

        gate = halting_gate(abort_clause) or return nil
        [method, gate]
      end

      # `current_user` in `unless current_user` / `if !current_user` — the bare
      # self-send being tested for presence. Returns the method name or nil.
      def presence_condition_method(cond)
        node = cond
        node = node.children[0] if node.is_a?(Parser::AST::Node) && node.type == :send && node.children[1] == :! && node.children[0]
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :send
        return nil unless node.children[0].nil? || node.children[0].type == :self
        return nil unless node.children[2..].to_a.empty? # no args

        node.children[1]
      end

      def clause_returns?(clause)
        walk_nodes(clause) { |n| return true if n.type == :return }
        false
      end

      # How the abort clause halts: a direct ivar write (`{ gate_ivar: }`) or,
      # failing that, the first self-method it calls (`{ gate_via: }`, resolved
      # to that method's written ivar by the Runner). nil if it does neither.
      def halting_gate(clause)
        walk_nodes(clause) do |n|
          return { gate_ivar: n.children[0] } if n.type == :ivasgn
        end
        walk_nodes(clause) do |n|
          next unless n.type == :send
          receiver = n.children[0]
          return { gate_via: n.children[1] } if receiver.nil? || receiver.type == :self
        end
        nil
      end

      # The declared return type of `self.<method>`, with `nil` subtracted —
      # the type it has on the proven-present exit. nil when the method has no
      # such declaration or isn't actually nilable.
      def nonnil_return_of_self_method(method, class_name, singleton:)
        type_name = RBS::TypeName.parse("::#{class_name}").absolute! rescue (return nil)
        definition =
          if singleton
            @definition_builder.build_singleton(type_name) rescue nil
          else
            @definition_builder.build_instance(type_name) rescue nil
          end
        return nil unless definition

        method_def = definition.methods[method] or return nil
        return_types = method_def.method_types.map { |mt| @factory.type(mt.type.return_type) }
        return nil if return_types.empty?

        ret = return_types.size == 1 ? return_types.first : AST::Types::Union.build(types: return_types)
        nonnil = subtract_nil(ret)
        nonnil unless nonnil == ret
      end

      def subtract_nil(type)
        return type unless type.is_a?(AST::Types::Union)

        remaining = type.types.reject { |t| t.is_a?(AST::Types::Nil) }
        return type if remaining.size == type.types.size
        return AST::Builtin.nil_type if remaining.empty?

        remaining.size == 1 ? remaining.first : AST::Types::Union.build(types: remaining)
      end

      # Yields each top-level statement of a (possibly `:begin`) body.
      def each_statement(body)
        if body.type == :begin
          body.children.each { |c| yield c if c.is_a?(Parser::AST::Node) }
        else
          yield body
        end
      end

      # Every `:send`/`:csend` descendant, including those inside block bodies —
      # the halt of a controller guard sits two blocks deep
      # (`respond_to { |f| f.html { redirect_to … } }`), and the block runs in
      # the same `self`, so its sends are ours.
      def walk_sends(node, &block)
        return unless node.is_a?(Parser::AST::Node)
        yield node if node.type == :send || node.type == :csend
        node.children.each do |child|
          walk_sends(child, &block) if child.is_a?(Parser::AST::Node)
        end
      end

      # Every descendant node (including the node itself).
      def walk_nodes(node, &block)
        return unless node.is_a?(Parser::AST::Node)
        yield node
        node.children.each do |child|
          walk_nodes(child, &block) if child.is_a?(Parser::AST::Node)
        end
      end

      # Recursively walks `node` yielding every `:ivasgn` descendant.
      def walk_ivasgns(node, &block)
        return unless node.is_a?(Parser::AST::Node)
        yield node if node.type == :ivasgn
        node.children.each do |child|
          walk_ivasgns(child, &block) if child.is_a?(Parser::AST::Node)
        end
      end

      def declared_ivar_types(class_name, singleton:)
        return {} if class_name.empty?
        type_name = RBS::TypeName.parse("::#{class_name}").absolute!
        definition =
          if singleton
            @definition_builder.build_singleton(type_name) rescue nil
          else
            @definition_builder.build_instance(type_name) rescue nil
          end
        return {} unless definition
        definition.instance_variables.transform_values do |ivar|
          @factory.type(ivar.type)
        end
      end

    end

    # Minimal value object for an inferred entry. Distinct from
    # `Postconditions::Entry` (which represents loaded YAML entries) so
    # callers can serialize the inference output without round-tripping
    # through the loader.
    class InferredEntry
      attr_reader :class_name, :method_name, :singleton
      attr_reader :ivars, :self_type_string
      attr_reader :when_true_ivars, :when_true_self_type_string
      # Array[Symbol] of attribute names the method establishes non-nil
      # on its returned value (felixefelip/steep#56).
      attr_reader :returns_establishes
      # Set[Symbol] of ivars the method may write, directly or transitively
      # (felixefelip/steep#68). `self_call_deps` are the call-graph edges the
      # Runner closes over to compute the transitive part; they are not
      # serialized.
      attr_reader :may_write_ivars, :self_call_deps
      # felixefelip/steep#68 item 2. `returns_ivar`: this method transparently
      # reads that ivar (halt-check getter). `conditional_returns`:
      # { method => { gate_ivar:, type: } } self-methods proven non-nil on the
      # unhalted exit, gated by the ivar's falsy state.
      attr_reader :returns_ivar, :conditional_returns
      # felixefelip/steep#68 item 3: { "Const.attr" => { gate_ivar:, type: } } —
      # constant attributes proven non-nil on the unhalted exit.
      attr_reader :conditional_const_returns
      # felixefelip/steep#68 item 5. `establishes_consts` (instance setters): other
      # attributes set non-nil when the setter's arg is non-nil. `delegates_to_instance`
      # (singleton setters): whether `self.x=` forwards to `instance.x=`.
      attr_reader :establishes_consts, :delegates_to_instance

      def initialize(class_name:, method_name:, singleton:, ivars: {}, self_type_string: nil, when_true_ivars: {}, when_true_self_type_string: nil, returns_establishes: [], may_write_ivars: Set[], self_call_deps: Set[], returns_ivar: nil, conditional_returns: {}, conditional_const_returns: {}, establishes_consts: {}, delegates_to_instance: false)
        @class_name = class_name
        @method_name = method_name
        @singleton = singleton
        @ivars = ivars
        @self_type_string = self_type_string
        @when_true_ivars = when_true_ivars
        @when_true_self_type_string = when_true_self_type_string
        @returns_establishes = returns_establishes
        @may_write_ivars = may_write_ivars
        @self_call_deps = self_call_deps
        @returns_ivar = returns_ivar
        @conditional_returns = conditional_returns
        @conditional_const_returns = conditional_const_returns
        @establishes_consts = establishes_consts
        @delegates_to_instance = delegates_to_instance
      end

      # A copy with `may_write_ivars` replaced — the Runner's fixpoint result.
      def with_may_write(ivars)
        InferredEntry.new(
          class_name: class_name, method_name: method_name, singleton: singleton,
          ivars: self.ivars, self_type_string: self_type_string,
          when_true_ivars: when_true_ivars, when_true_self_type_string: when_true_self_type_string,
          returns_establishes: returns_establishes,
          may_write_ivars: ivars, self_call_deps: self_call_deps,
          returns_ivar: returns_ivar, conditional_returns: conditional_returns,
          conditional_const_returns: conditional_const_returns,
          establishes_consts: establishes_consts, delegates_to_instance: delegates_to_instance
        )
      end

      # Whether the entry says anything a consumer can use. Entries that exist
      # only as call-graph nodes (no refinement, no effect) are dropped after
      # the fixpoint.
      def empty?
        ivars.empty? && when_true_ivars.empty? && returns_establishes.empty? &&
          may_write_ivars.empty? && returns_ivar.nil? && conditional_returns.empty? &&
          conditional_const_returns.empty?
      end

      def ==(other)
        other.is_a?(InferredEntry) &&
          other.class_name == class_name &&
          other.method_name == method_name &&
          other.singleton == singleton &&
          other.ivars == ivars &&
          other.self_type_string == self_type_string &&
          other.when_true_ivars == when_true_ivars &&
          other.when_true_self_type_string == when_true_self_type_string &&
          other.returns_establishes == returns_establishes &&
          other.may_write_ivars == may_write_ivars
      end

      alias eql? ==

      def hash
        class_name.hash ^ method_name.hash ^ singleton.hash ^ ivars.hash ^ self_type_string.hash ^
          when_true_ivars.hash ^ when_true_self_type_string.hash ^ returns_establishes.hash ^
          may_write_ivars.hash
      end
    end
  end
end
