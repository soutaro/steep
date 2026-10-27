module Steep
  module SetTheoretic
    # Decides whether a type is empty, reading the types as sets of values.
    #
    # Subtyping is emptiness: `S <: T` holds when `S & !T` is empty. The check normalizes the type to its DNF and decides
    # each clause from the class hierarchy: two unrelated classes have no common instance, a literal belongs to its own
    # class only, a module has an instance only when some class mixes it in, and so on. The answer is a `Verdict`, so
    # that the evidence from the RBS environment alone (`empty_in_rbs`) is told from the evidence that holds whatever
    # happens at runtime (`empty`).
    #
    # `untyped` is not a set. The `mode` says how to read it:
    #
    # - `:subtyping` makes the type as small as possible, so that `untyped <: T` and `T <: untyped` hold (a positive
    #   `untyped` is `bot`, a negated one is `!top`)
    # - `:inhabitation` makes the type as large as possible, so that a branch guarded by an `untyped` value is reachable
    #   (a positive `untyped` is `top`, a negated one is `!bot`)
    #
    # Tuples are products: `[A, B] & ![C, D]` is empty when `A <: C` and `B <: D`, and a tuple is also an instance of
    # `Array`. Procs are arrows: the parameters, the keywords, and the block make the domain, read as a union of
    # tuples, and `(^(A) -> B) & (^(C) -> D) <: ^(A | C) -> (B | D)` holds; a proc is also an instance of `Proc`.
    # Records count as instances of `Hash` when they are positive, and interfaces, procs with a `self` binding, type
    # variables without a bound, and `self`, `instance`, and `class` are opaque atoms that only cancel with their own
    # negation.
    class Emptiness
      MODES = [:subtyping, :inhabitation].freeze #: Array[mode]

      # The marker of an absent optional keyword or block in the domain of a proc: an instance of a class no environment
      # declares, which the check keeps opaque, so that it overlaps with no other type
      ABSENT = AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Steep::SetTheoretic::AbsentValue"), args: []) #: AST::Types::Name::Instance

      attr_reader :factory

      attr_reader :class_index

      attr_reader :normalizer

      def initialize(factory:, class_index: nil)
        @factory = factory
        @class_index = class_index || ClassIndex.new(env: factory.env, ancestor_builder: factory.definition_builder.ancestor_builder)
        @normalizer = Normalizer.new(factory: factory)
        @cache = {}
        @assumptions = Set[]
        @instance_views = {}
        @singleton_views = {}
      end

      def env
        factory.env
      end

      # The verdict of `type`
      #
      # `bounds` gives the upper bounds of the type variables in scope.
      def check(type, mode:, bounds: {})
        MODES.include?(mode) or raise ArgumentError, "Unknown mode: #{mode.inspect}"

        ground = type.free_variables.empty?
        cache_key = [type, mode] #: cache_key
        if ground && (cached = @cache[cache_key])
          return cached
        end

        assumption = [type, mode, bounds] #: assumption
        if @assumptions.include?(assumption)
          # The type is being checked already: assume it is empty, so that a recursive type is empty when it is only
          # inhabited by itself
          return Verdict.empty("assumed while checking `#{type}`")
        end

        @assumptions << assumption
        begin
          verdict = check_dnf(normalizer.normalize(type), mode, bounds)
        ensure
          @assumptions.delete(assumption)
        end

        @cache[cache_key] = verdict if ground
        verdict
      end

      # The verdict of `sub & !sup`: `empty` means `sub <: sup`
      def subtype?(sub_type, super_type, bounds: {})
        check(
          AST::Types::Intersection.build(types: [sub_type, AST::Types::Negation.build(type: super_type)]),
          mode: :subtyping,
          bounds: bounds
        )
      end

      # `true` if `sub <: sup`
      def subtype(sub_type, super_type, bounds: {})
        subtype?(sub_type, super_type, bounds: bounds).empty?
      end

      # The verdict of `type1 & type2`, read for reachability: `empty` means no value can have both types
      def disjoint?(type1, type2, bounds: {})
        check(AST::Types::Intersection.build(types: [type1, type2]), mode: :inhabitation, bounds: bounds)
      end

      def check_dnf(dnf, mode, bounds)
        dnf.clauses.inject(Verdict.empty) do |verdict, clause|
          verdict = verdict | check_clause(clause, mode, bounds)
          break verdict if verdict.inhabited?
          verdict
        end
      end

      # A positive atom of a clause, seen through the class hierarchy
      class Positive
        # The instance type (the literal's class for a literal, `Class` or `Module` for a singleton)
        attr_reader :name

        # The ancestors of the instance type with the type arguments applied: `name => args`
        attr_reader :views

        # The singleton ancestors of a singleton type
        attr_reader :singletons

        # The singleton class name of a singleton type
        attr_reader :singleton_name

        # The literal value of a literal type, `nil` for `nil`; `NO_VALUE` for the other types
        attr_reader :value

        NO_VALUE = Object.new.freeze #: Object

        def initialize(name:, views:, singletons: Set[], singleton_name: nil, value: NO_VALUE)
          @name = name
          @views = views
          @singletons = singletons
          @singleton_name = singleton_name
          @value = value
        end

        def exact?
          !value.equal?(NO_VALUE)
        end

        def singleton?
          singleton_name ? true : false
        end

        def has_ancestor?(name)
          views.key?(name)
        end
      end

      def check_clause(clause, mode, bounds)
        positives = clause.positives.to_a
        negatives = clause.negatives.to_a

        # `untyped`
        any = AST::Types::Any.instance
        case mode
        when :subtyping
          if positives.include?(any)
            return Verdict.empty("`untyped` is read as `bot`")
          end
          if negatives.include?(any)
            return Verdict.empty("`!untyped` is read as `!top`")
          end
        when :inhabitation
          positives.delete(any)
          negatives.delete(any)
        end

        # Type variables
        vars = positives.select {|type| type.is_a?(AST::Types::Var) } #: Array[AST::Types::Var]
        vars.each do |var|
          if negatives.include?(var)
            return Verdict.empty("`#{var}` is both required and excluded")
          end
        end
        bounded = vars.select {|var| bounds[var.name] }
        unless bounded.empty?
          # The clause is a subset of the one with the bounds in place of the variables
          type = AST::Types::Intersection.build(
            types: positives.map {|ty| ty.is_a?(AST::Types::Var) && (bound = bounds[ty.name]) ? bound : ty } +
              negatives.map {|ty| AST::Types::Negation.build(type: ty) }
          )
          return check(type, mode: mode, bounds: bounds.reject {|name, _| bounded.any? {|var| var.name == name } })
        end
        negatives.reject! {|type| type.is_a?(AST::Types::Var) }

        rbs_reasons = [] #: Array[String]

        # The positive atoms the class hierarchy knows about
        nominals = positives.filter_map {|type| positive(type) }
        values = nominals.select(&:exact?)
        if (first_value = values.first)
          values.each do |value|
            if value.value != first_value.value
              return Verdict.empty("`#{first_value.value.inspect}` and `#{value.value.inspect}` are different values")
            end
          end
        end

        # Classes, literals, and singletons must form a chain of subclasses
        most = nil #: Positive?
        nominals.each do |nominal|
          next if class_index.module?(nominal.name) && !nominal.singleton?

          if most
            case
            when subclass?(nominal, most)
              # The same class, or a class below it
              if most.exact? && nominal.name != most.name
                return Verdict.empty("`#{most.value.inspect}` is not an instance of `#{nominal.name}`")
              end
              most = nominal if nominal.name != most.name || nominal.exact?
            when subclass?(most, nominal)
              if nominal.exact? && nominal.name != most.name
                return Verdict.empty("`#{nominal.value.inspect}` is not an instance of `#{most.name}`")
              end
            else
              return Verdict.empty("`#{describe(most)}` and `#{describe(nominal)}` have no common instance")
            end
          else
            most = nominal
          end
        end

        # Modules must be ancestors of the chain, or mixed in by a class below it
        modules = nominals.select {|nominal| class_index.module?(nominal.name) && !nominal.singleton? }
        if most
          modules.each do |mod|
            next if most.has_ancestor?(mod.name)

            case
            when most.exact?
              rbs_reasons << "`#{most.name}` does not include `#{mod.name}`"
            when most.singleton?
              unless class_index.singleton_extends?(most.singleton_name || raise, mod.name)
                rbs_reasons << "`singleton(#{most.singleton_name})` does not extend `#{mod.name}`"
              end
            else
              unless class_index.common_instance?(most.name, mod.name)
                rbs_reasons << "no class under `#{most.name}` includes `#{mod.name}`"
              end
            end
          end
        else
          modules.each_with_index do |m1, index|
            modules.drop(index + 1).each do |m2|
              next if m1.has_ancestor?(m2.name) || m2.has_ancestor?(m1.name)
              unless class_index.common_instance?(m1.name, m2.name)
                rbs_reasons << "no class includes both `#{m1.name}` and `#{m2.name}`"
              end
            end
          end
        end

        # The type arguments of each ancestor, as seen from each positive atom
        all_views = {} #: Hash[RBS::TypeName, Array[Array[AST::Types::t]]]
        nominals.each do |nominal|
          nominal.views.each do |name, args|
            (all_views[name] ||= []) << args
          end
        end

        # Tuples
        tuples = positives.grep(AST::Types::Tuple)
        unless tuples.empty?
          verdict = check_tuples(tuples, positives, negatives, mode, bounds)
          case
          when verdict.empty?
            return verdict
          when verdict.empty_in_rbs?
            rbs_reasons << (verdict.reason || "the tuple is empty")
          end
        end

        # Arrows
        verdict = check_arrows(positives, negatives, mode, bounds)
        case
        when verdict.empty?
          return verdict
        when verdict.empty_in_rbs?
          rbs_reasons << (verdict.reason || "the procs are excluded")
        end

        negatives.each do |negative|
          case negative
          when AST::Types::Literal, AST::Types::Nil
            value = negative.is_a?(AST::Types::Literal) ? negative.value : nil
            if values.any? {|v| v.value == value }
              return Verdict.empty("`#{negative}` is both required and excluded")
            end
          when AST::Types::Name::Singleton
            name = env.normalize_module_name(negative.name)
            nominals.each do |nominal|
              if nominal.singleton? && nominal.singletons.include?(name)
                return Verdict.empty("`#{describe(nominal)}` is a `#{negative}`")
              end
            end
          when AST::Types::Name::Instance
            name = env.normalize_module_name(negative.name)
            if (views = all_views[name])
              verdict = covered?(name, negative.args, views, mode, bounds)
              case
              when verdict.empty?
                return Verdict.empty("`#{negative}` excludes the instances of `#{most ? describe(most) : name}`")
              when verdict.empty_in_rbs?
                rbs_reasons << (verdict.reason || "`#{negative}` excludes the instances of `#{name}`")
              end
            elsif most.nil? && !modules.empty? && class_index.class?(name)
              classes = modules.map {|mod| class_index.instance_classes(mod.name) }.inject {|s1, s2| s1 & s2 } or raise
              if !classes.empty? && classes.subset?(class_index.instance_classes(name))
                rbs_reasons << "every class including `#{modules.map(&:name).join("`, `")}` inherits from `#{name}`"
              end
            end
          end
        end

        if (reason = rbs_reasons.first)
          Verdict.empty_in_rbs(reason)
        else
          Verdict.inhabited
        end
      end

      # The verdict of the tuples of a clause: the positive tuples intersected component-wise, minus the negative tuples
      # and the negative `Array[T]`-like atoms, which exclude the tuples whose components are all `T`
      def check_tuples(tuples, positives, negatives, mode, bounds)
        arity = tuples.first&.types&.size or raise
        unless tuples.all? {|tuple| tuple.types.size == arity }
          return Verdict.empty("tuples of different lengths have no common value")
        end

        components = Array.new(arity) do |index|
          AST::Types::Intersection.build(types: tuples.map {|tuple| tuple.types.fetch(index) })
        end

        # `[A, B] & Array[T]` is `[A & T, B & T]`
        positives.each do |positive|
          if positive.is_a?(AST::Types::Name::Instance) && (element = tuple_element_type(positive))
            components = components.map {|component| AST::Types::Intersection.build(types: [component, element]) }
          end
        end

        negative_tuples = [] #: Array[Array[AST::Types::t]]
        negatives.each do |negative|
          case negative
          when AST::Types::Tuple
            negative_tuples << negative.types if negative.types.size == arity
          when AST::Types::Name::Instance
            if (element = tuple_element_type(negative))
              negative_tuples << Array.new(arity, element)
            end
          end
        end

        tuple_empty?(components, negative_tuples, mode, bounds)
      end

      # The element type of an `Array[T]`-like instance type, one whose only type argument is the element type of the
      # arrays (`Array[T]` and `Enumerable[T]`); `nil` for the other types
      def tuple_element_type(type)
        element = AST::Types::Var.new(name: :__tuple_element__)
        @tuple_element_ancestors ||= begin
          views = instance_views(AST::Builtin::Array.instance_type(element)) || {}
          views.filter_map {|name, args| name if args == [element] }.to_set
        end

        if @tuple_element_ancestors.include?(env.normalize_module_name(type.name)) && type.args.size == 1
          type.args.fetch(0)
        end
      end

      # The verdict of `[c1, ..., ck] & ![n1, ..., nk] & ...`
      #
      # A tuple with an empty component has no value, and `[c1, c2] & ![n1, n2]` is `[c1 & !n1, c2] | [c1, c2 & !n2]`.
      def tuple_empty?(components, negatives, mode, bounds)
        verdict = Verdict.inhabited
        components.each do |component|
          verdict = verdict & check(component, mode: mode, bounds: bounds)
          return verdict if verdict.empty?
        end
        return verdict if negatives.empty?

        negative, *rest = negatives
        negative or raise

        result = Verdict.empty
        components.each_with_index do |component, index|
          refined = components.dup
          refined[index] = AST::Types::Intersection.build(
            types: [component, AST::Types::Negation.build(type: negative[index] || AST::Types::Any.instance)]
          )
          result = result | tuple_empty?(refined, rest, mode, bounds)
          return result if result.inhabited?
        end

        # The components may be empty in the environment only, which the recursion reports the same way
        result & verdict
      end

      # The shape the domains of the arrows of a clause are encoded with: the same lengths and keyword names for all of
      # them, so that they are comparable tuples
      class ArrowUniverse
        # The longest argument list considered
        attr_reader :max_length

        # The keyword names of all of the arrows
        attr_reader :keywords

        def initialize(arrows, positive_count)
          lengths = [] #: Array[Integer]
          rest = false
          names = Set[] #: Set[Symbol]

          arrows.each do |arrow|
            params = arrow.type.params or next
            lengths << params.required.size + params.optional.size
            rest ||= params.rest ? true : false
            names.merge(params.required_keywords.each_key)
            names.merge(params.optional_keywords.each_key)
          end

          longest = lengths.max || 0
          # Beyond the optional parameters only the rest parameters are left, and an argument list that long is
          # covered by the arrows when every one of the next `positive_count` lengths is
          @max_length = rest ? longest + positive_count : longest
          @keywords = names.to_a.sort
        end
      end

      # The verdict of the arrows of a clause: `empty` when a negative arrow covers the intersection of the positive ones
      #
      # The arrows with a `self` binding are opaque and left out.
      def check_arrows(positives, negatives, mode, bounds)
        arrows = positives.grep(AST::Types::Proc).reject(&:self_type)
        return Verdict.inhabited if arrows.empty?
        negative_arrows = negatives.grep(AST::Types::Proc).reject(&:self_type)
        return Verdict.inhabited if negative_arrows.empty?

        universe = ArrowUniverse.new(arrows + negative_arrows, arrows.size)

        verdict = Verdict.inhabited
        negative_arrows.each do |negative|
          negative_domain = domain(negative, universe)

          # A proc is total on its domain: calling it outside raises, which `^(Integer) -> void <: ^(Integer, ?String) -> void`
          # must not allow, so the domain of the negative arrow must be covered by the domains of the positive ones
          coverage = check(
            AST::Types::Intersection.build(
              types: [negative_domain] + arrows.map {|arrow| AST::Types::Negation.build(type: domain(arrow, universe)) }
            ),
            mode: mode,
            bounds: bounds
          )
          next if coverage.inhabited?

          covered = coverage | phi(
            negative_domain,
            AST::Types::Negation.build(type: negative.type.return_type),
            arrows,
            universe,
            mode,
            bounds
          )
          unless covered.inhabited?
            covered = Verdict.new(covered.kind, "`#{negative}` covers the procs")
          end
          verdict = verdict & covered
          return verdict if verdict.empty?
        end

        verdict
      end

      # `empty` when `arrows` (an intersection) is a subtype of `s -> !t`: `Φ(s, t, ∅)` is `s` or `t` empty, and
      # `Φ(s, t, (s1 -> t1) :: P)` is `Φ(s & !s1, t, P)` and `Φ(s, t & t1, P)`
      def phi(domain_type, codomain_type, arrows, universe, mode, bounds)
        domain_verdict = check(domain_type, mode: mode, bounds: bounds)
        return domain_verdict unless domain_verdict.inhabited?
        codomain_verdict = check(codomain_type, mode: mode, bounds: bounds)
        return codomain_verdict unless codomain_verdict.inhabited?
        return Verdict.inhabited if arrows.empty?

        arrow, *rest = arrows
        arrow or raise

        left = phi(
          AST::Types::Intersection.build(types: [domain_type, AST::Types::Negation.build(type: domain(arrow, universe))]),
          codomain_type,
          rest,
          universe,
          mode,
          bounds
        )
        return left if left.inhabited?

        right = phi(
          domain_type,
          AST::Types::Intersection.build(types: [codomain_type, arrow.type.return_type]),
          rest,
          universe,
          mode,
          bounds
        )

        # Both must hold
        left | right
      end

      # The domain of an arrow: the argument lists it accepts, as a union of tuples
      #
      # A tuple has the positional arguments, then the keywords of the universe (`ABSENT` when the arrow has no such
      # keyword, or the rest keywords), the rest keywords, and the block (`nil` when the arrow takes none).
      def domain(arrow, universe)
        params = arrow.type.params or return AST::Types::Top.instance

        keywords = universe.keywords.map do |name|
          case
          when (type = params.required_keywords[name])
            type
          when (type = params.optional_keywords[name])
            AST::Types::Union.build(types: [type, ABSENT])
          when (type = params.rest_keywords)
            AST::Types::Union.build(types: [type, ABSENT])
          else
            ABSENT
          end
        end
        rest_keywords =
          if (type = params.rest_keywords)
            AST::Types::Union.build(types: [type, ABSENT])
          else
            ABSENT
          end

        block =
          if (block = arrow.block)
            block_type = AST::Types::Proc.new(type: block.type, block: nil, self_type: block.self_type)
            if block.optional?
              AST::Types::Union.build(types: [block_type, AST::Builtin.nil_type])
            else
              block_type
            end
          else
            AST::Builtin.nil_type
          end

        required = params.required
        optional = params.optional
        longest = params.rest ? universe.max_length : required.size + optional.size

        tuples = (required.size..longest).map do |length|
          positional = required + optional.take(length - required.size)
          if (rest = params.rest)
            positional += Array.new(length - positional.size, rest)
          end
          AST::Types::Tuple.new(types: positional + keywords + [rest_keywords, block])
        end

        AST::Types::Union.build(types: tuples)
      end

      # The verdict of `C[a] & !D[b]` for the type arguments, given the views `a` of `D` from the positive atoms:
      # `empty` means the negative atom excludes all of the positive atoms
      def covered?(name, negative_args, views, mode, bounds)
        params = type_params(name)
        return Verdict.empty if params.empty?

        any = AST::Types::Any.instance

        verdict = Verdict.empty
        params.each_with_index do |param, index|
          negative_arg = negative_args[index] || any
          positive_args = views.map {|args| args[index] || any }

          param_verdict =
            case param.variance
            when :covariant
              check(
                AST::Types::Intersection.build(
                  types: [AST::Types::Intersection.build(types: positive_args), AST::Types::Negation.build(type: negative_arg)]
                ),
                mode: mode,
                bounds: bounds
              )
            when :contravariant
              check(
                AST::Types::Intersection.build(
                  types: [negative_arg, AST::Types::Negation.build(type: AST::Types::Union.build(types: positive_args))]
                ),
                mode: mode,
                bounds: bounds
              )
            else
              # The negative atom excludes the positive ones only when the arguments are equivalent
              positive_args.map do |positive_arg|
                check(AST::Types::Intersection.build(types: [positive_arg, AST::Types::Negation.build(type: negative_arg)]), mode: mode, bounds: bounds) |
                  check(AST::Types::Intersection.build(types: [negative_arg, AST::Types::Negation.build(type: positive_arg)]), mode: mode, bounds: bounds)
              end.inject {|v1, v2| v1 & v2 } || Verdict.inhabited
            end

          verdict = verdict | param_verdict
          break if verdict.inhabited?
        end
        verdict
      end

      def type_params(name)
        if entry = env.class_decls[name]
          entry.type_params
        else
          []
        end
      end

      # `true` if the instance type of `sub` is a subclass of the one of `sup` (or the same class)
      def subclass?(sub, sup)
        if sub.singleton? && sup.singleton?
          sub.singletons.include?(sup.singleton_name || raise)
        else
          sub.name == sup.name || sub.has_ancestor?(sup.name)
        end
      end

      def describe(positive)
        case
        when positive.exact?
          positive.value.inspect
        when positive.singleton?
          "singleton(#{positive.singleton_name})"
        else
          positive.name.to_s
        end
      end

      # The nominal view of a positive atom; `nil` for an opaque atom
      def positive(type)
        case type
        when AST::Types::Name::Instance
          instance_positive(type)
        when AST::Types::Name::Singleton
          singleton_positive(type)
        when AST::Types::Literal
          instance_positive(type.back_type, value: type.value)
        when AST::Types::Nil
          instance_positive(AST::Builtin::NilClass.instance_type, value: nil)
        when AST::Types::Tuple
          instance_positive(AST::Builtin::Array.instance_type(AST::Types::Union.build(types: type.types)))
        when AST::Types::Record
          instance_positive(
            AST::Builtin::Hash.instance_type(
              AST::Types::Union.build(types: type.elements.each_key.map {|key| AST::Types::Literal.new(value: key) }),
              AST::Types::Union.build(types: type.elements.values)
            )
          )
        when AST::Types::Proc
          instance_positive(AST::Builtin::Proc.instance_type)
        end
      end

      def instance_positive(type, value: Positive::NO_VALUE)
        views = instance_views(type) or return
        Positive.new(name: env.normalize_module_name(type.name), views: views, value: value)
      end

      def singleton_positive(type)
        name = env.normalize_module_name(type.name)
        pair = singleton_views(name) or return
        views, singletons = pair
        instance_name = class_index.class?(name) ? AST::Builtin::Class.module_name : AST::Builtin::Module.module_name
        Positive.new(name: instance_name, views: views, singletons: singletons, singleton_name: name)
      end

      # The instance ancestors of an instance type with the type arguments applied: `name => args`; `nil` if the class
      # is unknown
      def instance_views(type)
        @instance_views[type] ||= begin
          name = env.normalize_module_name(type.name)
          if env.class_decls.key?(name)
            ancestors = factory.definition_builder.ancestor_builder.instance_ancestors(name)
            subst = Interface::Substitution.build(
              ancestors.params,
              ancestors.params.each_with_index.map {|_, index| type.args[index] || AST::Types::Any.instance }
            )
            views = {} #: Hash[RBS::TypeName, Array[AST::Types::t]]
            ancestors.ancestors.each do |ancestor|
              if ancestor.is_a?(RBS::Definition::Ancestor::Instance) && ancestor.name.class?
                views[env.normalize_module_name(ancestor.name)] = ancestor.args.map {|arg| factory.type(arg).subst(subst) }
              end
            end
            views
          end
        rescue RBS::BaseError
          nil
        end
      end

      # The singleton ancestors of a class or module: the instance ancestors (`Class`, extended modules, ...) with their
      # arguments, and the singleton ancestors (the singletons of the superclasses)
      def singleton_views(name)
        @singleton_views[name] ||= begin
          if env.class_decls.key?(name)
            ancestors = factory.definition_builder.ancestor_builder.singleton_ancestors(name)
            views = {} #: Hash[RBS::TypeName, Array[AST::Types::t]]
            singletons = Set[] #: Set[RBS::TypeName]
            ancestors.ancestors.each do |ancestor|
              case ancestor
              when RBS::Definition::Ancestor::Instance
                if ancestor.name.class?
                  views[env.normalize_module_name(ancestor.name)] = ancestor.args.map {|arg| factory.type(arg) }
                end
              when RBS::Definition::Ancestor::Singleton
                singletons << env.normalize_module_name(ancestor.name)
              end
            end
            [views, singletons]
          end
        rescue RBS::BaseError
          nil
        end
      end
    end
  end
end
