module Steep
  module Subtyping
    class Check
      attr_reader :factory
      attr_reader :cache

      def initialize(factory:)
        @factory = factory
        @cache = {}
      end

      def check(relation, constraints:, assumption: Set.new, trace: Trace.new)
        Steep.logger.tagged "#{relation.sub_type} <: #{relation.super_type}" do
          prefix = trace.size
          cached = cache[relation]
          if cached && constraints.empty?
            if cached.success?
              cached
            else
              cached.merge_trace(trace)
            end
          else
            if assumption.member?(relation)
              success(constraints: constraints)
            else
              assumption = assumption + Set.new([relation])
              check0(relation, assumption: assumption, trace: trace, constraints: constraints).tap do |result|
                result = result.else do |failure|
                  failure.drop(prefix)
                end

                Steep.logger.debug "result=#{result.class}"
                cache[relation] = result if cacheable?(relation)
              end
            end
          end
        end
      end

      def alias?(type)
        type.is_a?(AST::Types::Name::Alias)
      end

      def cacheable?(relation)
        relation.sub_type.free_variables.empty? && relation.super_type.free_variables.empty?
      end

      def success(constraints:)
        Result::Success.new(constraints: constraints)
      end

      def failure(error:, trace:)
        Result::Failure.new(error: error, trace: trace)
      end

      def check0(relation, assumption:, trace:, constraints:)
        # puts relation
        trace.type(relation.sub_type, relation.super_type) do
          case
          when same_type?(relation, assumption: assumption)
            success(constraints: constraints)

          when relation.sub_type.is_a?(AST::Types::Any) || relation.super_type.is_a?(AST::Types::Any)
            success(constraints: constraints)

          when relation.super_type.is_a?(AST::Types::Void)
            success(constraints: constraints)

          when relation.super_type.is_a?(AST::Types::Top)
            success(constraints: constraints)

          when relation.sub_type.is_a?(AST::Types::Bot)
            success(constraints: constraints)

          when relation.super_type.is_a?(AST::Types::Boolean)
            success(constraints: constraints)

          when alias?(relation.sub_type)
            check0(
              Relation.new(sub_type: expand_alias(relation.sub_type), super_type: relation.super_type),
              assumption: assumption,
              trace: trace,
              constraints: constraints
            )

          when alias?(relation.super_type)
            check0(
              Relation.new(super_type: expand_alias(relation.super_type), sub_type: relation.sub_type),
              assumption: assumption,
              trace: trace,
              constraints: constraints
            )

          when relation.sub_type.is_a?(AST::Types::Literal)
            check0(
              Relation.new(sub_type: relation.sub_type.back_type, super_type: relation.super_type),
              assumption: assumption,
              trace: trace,
              constraints: constraints
            )

          when relation.sub_type.is_a?(AST::Types::Union)
            results = relation.sub_type.types.map do |sub_type|
              check0(Relation.new(sub_type: sub_type, super_type: relation.super_type),
                     assumption: assumption,
                     trace: trace,
                     constraints: constraints)
            end

            if results.all?(&:success?)
              results.first
            else
              results.find(&:failure?)
            end

          when relation.super_type.is_a?(AST::Types::Union)
            results = relation.super_type.types.map do |super_type|
              check0(Relation.new(sub_type: relation.sub_type, super_type: super_type),
                     assumption: assumption,
                     trace: trace,
                     constraints: constraints)
            end

            results.find(&:success?) || results.first

          when relation.sub_type.is_a?(AST::Types::Intersection)
            results = relation.sub_type.types.map do |sub_type|
              check0(Relation.new(sub_type: sub_type, super_type: relation.super_type),
                     assumption: assumption,
                     trace: trace,
                     constraints: constraints)
            end

            results.find(&:success?) || results.first

          when relation.super_type.is_a?(AST::Types::Intersection)
            results = relation.super_type.types.map do |super_type|
              check0(Relation.new(sub_type: relation.sub_type, super_type: super_type),
                     assumption: assumption,
                     trace: trace,
                     constraints: constraints)
            end

            if results.all?(&:success?)
              results.first
            else
              results.find(&:failure?)
            end

          when relation.super_type.is_a?(AST::Types::Var) && constraints.unknown?(relation.super_type.name)
            constraints.add(relation.super_type.name, sub_type: relation.sub_type)
            success(constraints: constraints)

          when relation.sub_type.is_a?(AST::Types::Var) && constraints.unknown?(relation.sub_type.name)
            constraints.add(relation.sub_type.name, super_type: relation.super_type)
            success(constraints: constraints)

          when relation.super_type.is_a?(AST::Types::Var) || relation.sub_type.is_a?(AST::Types::Var)
            failure(error: Result::Failure::UnknownPairError.new(relation: relation),
                    trace: trace)

          when relation.sub_type.is_a?(AST::Types::Name::Base) && relation.super_type.is_a?(AST::Types::Name::Base)
            if (pairs = extract_nominal_pairs(relation))
              results = pairs.flat_map do |(sub, sup)|
                Relation.new(sub_type: sub, super_type: sup).yield_self do |rel|
                  [rel, rel.flip]
                end
              end.map do |relation|
                check0(relation,
                       assumption: assumption,
                       trace: trace,
                       constraints: constraints)
              end

              if results.all?(&:success?)
                results.first
              else
                results.find(&:failure?)
              end
            else
              sub_interface = factory.interface(relation.sub_type, private: false)
              super_interface = factory.interface(relation.super_type, private: false)

              check_interface(sub_interface, super_interface, assumption: assumption, trace: trace, constraints: constraints)
            end

          when relation.sub_type.is_a?(AST::Types::Proc) && relation.super_type.is_a?(AST::Types::Proc)
            check_method_params(:__proc__,
                                relation.sub_type.params, relation.super_type.params,
                                assumption: assumption,
                                trace: trace,
                                constraints: constraints).then do
              check0(Relation.new(sub_type: relation.sub_type.return_type, super_type: relation.super_type.return_type),
                     assumption: assumption,
                     trace: trace,
                     constraints: constraints)
            end

          when relation.sub_type.is_a?(AST::Types::Tuple) && relation.super_type.is_a?(AST::Types::Tuple)
            if relation.sub_type.types.size >= relation.super_type.types.size
              pairs = relation.sub_type.types.take(relation.super_type.types.size).zip(relation.super_type.types)
              results = pairs.flat_map do |t1, t2|
                relation = Relation.new(sub_type: t1, super_type: t2)
                [check0(relation, assumption: assumption, trace: trace, constraints: constraints),
                 check0(relation.flip, assumption: assumption, trace: trace, constraints: constraints)]
              end

              if results.all?(&:success?)
                success(constraints: constraints)
              else
                results.find(&:failure?)
              end
            else
              failure(error: Result::Failure::UnknownPairError.new(relation: relation),
                      trace: trace)
            end

          when relation.sub_type.is_a?(AST::Types::Tuple) && relation.super_type.is_a?(AST::Types::Name::Base)
            tuple_interface = factory.interface(relation.sub_type, private: false)
            type_interface = factory.interface(relation.super_type, private: false)

            check_interface(tuple_interface,
                            type_interface,
                            assumption: assumption,
                            trace: trace,
                            constraints: constraints)

          when relation.sub_type.is_a?(AST::Types::Record) && relation.super_type.is_a?(AST::Types::Record)
            if Set.new(relation.sub_type.elements.keys).superset?(Set.new(relation.super_type.elements.keys))
              keys = relation.super_type.elements.keys
              type_pairs = keys.map {|key| [relation.sub_type.elements[key], relation.super_type.elements[key]] }
              results = type_pairs.flat_map do |t1, t2|
                relation = Relation.new(sub_type: t1, super_type: t2)
                [check0(relation, assumption: assumption, trace: trace, constraints: constraints),
                 check0(relation.flip, assumption: assumption, trace: trace, constraints: constraints)]
              end

              if results.all?(&:success?)
                success(constraints: constraints)
              else
                results.find(&:failure?)
              end
            else
              failure(error: Result::Failure::UnknownPairError.new(relation: relation),
                      trace: trace)
            end

          when relation.sub_type.is_a?(AST::Types::Record) && relation.super_type.is_a?(AST::Types::Name::Base)
            record_interface = factory.interface(relation.sub_type, private: false)
            type_interface = factory.interface(relation.super_type, private: false)

            check_interface(record_interface,
                            type_interface,
                            assumption: assumption,
                            trace: trace,
                            constraints: constraints)

          else
            failure(error: Result::Failure::UnknownPairError.new(relation: relation),
                    trace: trace)
          end
        end
      end
      
      def extract_nominal_pairs(relation)
        sub_type = relation.sub_type
        super_type = relation.super_type
        
        case
        when sub_type.is_a?(AST::Types::Name::Instance) && super_type.is_a?(AST::Types::Name::Instance)
          if sub_type.name == super_type.name && sub_type.args.size == super_type.args.size
            sub_type.args.zip(super_type.args)
          end
        when sub_type.is_a?(AST::Types::Name::Interface) && super_type.is_a?(AST::Types::Name::Interface)
          if sub_type.name == super_type.name && sub_type.args.size == super_type.args.size
            sub_type.args.zip(super_type.args)
          end
        when sub_type.is_a?(AST::Types::Name::Alias) && super_type.is_a?(AST::Types::Name::Alias)
          if sub_type.name == super_type.name && sub_type.args.size == super_type.args.size
            sub_type.args.zip(super_type.args)
          end
        when sub_type.is_a?(AST::Types::Name::Class) && super_type.is_a?(AST::Types::Name::Class)
          if sub_type.name == super_type.name
            []
          end
        when sub_type.is_a?(AST::Types::Name::Module) && super_type.is_a?(AST::Types::Name::Module)
          if sub_type.name == super_type.name
            []
          end
        end
      end

      def same_type?(relation, assumption:)
        if assumption.include?(relation) && assumption.include?(relation.flip)
          return true
        end

        case
        when relation.sub_type == relation.super_type
          true
        when relation.sub_type.is_a?(AST::Types::Name::Base) && relation.super_type.is_a?(AST::Types::Name::Base)
          if (pairs = extract_nominal_pairs(relation))
            pairs.all? do |(s, t)|
              same_type?(Relation.new(sub_type: s, super_type: t), assumption: assumption)
            end
          else
            false
          end
        else
          false
        end
      end

      def check_interface(sub_interface, super_interface, assumption:, trace:, constraints:)
        trace.interface sub_interface, super_interface do
          method_triples = []

          super_interface.methods.each do |name, sup_method|
            sub_method = sub_interface.methods[name]

            if sub_method
              method_triples << [name, sub_method, sup_method]
            else
              return failure(error: Result::Failure::MethodMissingError.new(name: name),
                             trace: trace)
            end
          end

          method_triples.each do |(method_name, sub_method, sup_method)|
            result = check_method(method_name,
                                  sub_method,
                                  sup_method,
                                  assumption: assumption,
                                  trace: trace,
                                  constraints: constraints)
            return result if result.failure?
          end

          success(constraints: constraints)
        end
      end

      def check_method(name, sub_method, super_method, assumption:, trace:, constraints:)
        trace.method name, sub_method, super_method do
          case
          when sub_method.overload? && super_method.overload?
            super_method.types.map do |super_type|
              sub_method.types.map do |sub_type|
                if super_type == :any || sub_type == :any
                  success constraints: constraints
                else
                  check_generic_method_type name,
                                            sub_type,
                                            super_type,
                                            assumption: assumption,
                                            trace: trace,
                                            constraints: constraints
                end
              end.yield_self do |results|
                results.find(&:success?) || results[0]
              end
            end.yield_self do |results|
              if results.all?(&:success?)
                success constraints: constraints
              else
                results.select(&:failure?).last
              end
            end
          else
            raise "aaaaaaaaaaaaaa"
          end
        end
      end

      def check_generic_method_type(name, sub_type, super_type, assumption:, trace:, constraints:)
        trace.method_type name, sub_type, super_type do
          case
          when sub_type.type_params.empty? && super_type.type_params.empty?
            check_method_type name,
                              sub_type,
                              super_type,
                              assumption: assumption,
                              trace: trace,
                              constraints: constraints

          when !sub_type.type_params.empty? && super_type.type_params.empty?
            # Check if super_type is an instance of sub_type.
            yield_self do
              sub_args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }
              sub_type = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, sub_args))

              constraints.add_var(*sub_args)

              match_method_type(name, sub_type, super_type, trace: trace).yield_self do |pairs|
                case pairs
                when Array
                  subst = pairs.each.with_object(Interface::Substitution.empty) do |(sub, sup), subst|
                    case
                    when sub.is_a?(AST::Types::Var) && sub_args.include?(sub)
                      if subst.key?(sub.name) && subst[sub.name] != sup
                        return failure(error: Result::Failure::PolyMethodSubtyping.new(name: name),
                                       trace: trace)
                      else
                        subst.add!(sub.name, sup)
                      end
                    when sup.is_a?(AST::Types::Var) && sub_args.include?(sup)
                      if subst.key?(sup.name) && subst[sup.name] != sub
                        return failure(error: Result::Failure::PolyMethodSubtyping.new(name: name),
                                       trace: trace)
                      else
                        subst.add!(sup.name, sub)
                      end
                    end
                  end

                  check_method_type(name,
                                    sub_type.subst(subst),
                                    super_type,
                                    assumption: assumption,
                                    trace: trace,
                                    constraints: constraints)
                else
                  pairs
                end
              end
            end

          when sub_type.type_params.empty? && !super_type.type_params.empty?
            # Check if sub_type is an instance of super_type && no constraints on type variables (any).
            yield_self do
              sub_args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }
              sub_type = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, sub_args))

              constraints.add_var(*sub_args)

              match_method_type(name, sub_type, super_type, trace: trace).yield_self do |pairs|
                case pairs
                when Array
                  result = check_method_type(name,
                                             sub_type,
                                             super_type,
                                             assumption: assumption,
                                             trace: trace,
                                             constraints: constraints)

                  if result.success? && sub_args.map(&:name).none? {|var| constraints.has_constraint?(var) }
                    result
                  else
                    failure(error: Result::Failure::PolyMethodSubtyping.new(name: name),
                            trace: trace)
                  end

                else
                  pairs
                end
              end
            end

          when super_type.type_params.size == sub_type.type_params.size
            # Check if they have the same shape
            yield_self do
              args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }

              sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, args))
              super_type_ = super_type.instantiate(Interface::Substitution.build(super_type.type_params, args))

              constraints.add_var(*args)

              check_method_type(name,
                                sub_type_,
                                super_type_,
                                assumption: assumption,
                                trace: trace,
                                constraints: constraints)
            end

          else
            # Or error
            failure(error: Result::Failure::PolyMethodSubtyping.new(name: name),
                    trace: trace)
          end
        end
      end

      def check_method_type(name, sub_type, super_type, assumption:, trace:, constraints:)
        Steep.logger.tagged("#{name}: #{sub_type} <: #{super_type}") do
          check_method_params(name, sub_type.params, super_type.params, assumption: assumption, trace: trace, constraints: constraints).then do
            check_block_given(name, sub_type.block, super_type.block, trace: trace, constraints: constraints).then do
              check_block_params(name, sub_type.block, super_type.block, assumption: assumption, trace: trace, constraints: constraints).then do
                check_block_return(sub_type.block, super_type.block, assumption: assumption, trace: trace, constraints:constraints).then do
                  relation = Relation.new(super_type: super_type.return_type,
                                          sub_type: sub_type.return_type)
                  check(relation, assumption: assumption, trace: trace, constraints: constraints)
                end
              end
            end
          end
        end
      end

      def check_block_given(name, sub_block, super_block, trace:, constraints:)
        case
        when !super_block && !sub_block
          success(constraints: constraints)
        when super_block && sub_block && super_block.optional? == sub_block.optional?
          success(constraints: constraints)
        when sub_block&.optional?
          success(constraints: constraints)
        else
          failure(
            error: Result::Failure::BlockMismatchError.new(name: name),
            trace: trace
          )
        end
      end

      def check_method_params(name, sub_params, super_params, assumption:, trace:, constraints:)
        match_params(name, sub_params, super_params, trace: trace).yield_self do |pairs|
          case pairs
          when Array
            pairs.each do |(sub_type, super_type)|
              relation = Relation.new(super_type: sub_type, sub_type: super_type)

              result = check(relation, assumption: assumption, trace: trace, constraints: constraints)
              return result if result.failure?
            end

            success(constraints: constraints)
          else
            pairs
          end
        end
      end

      def match_method_type(name, sub_type, super_type, trace:)
        [].tap do |pairs|
          match_params(name, sub_type.params, super_type.params, trace: trace).yield_self do |result|
            return result unless result.is_a?(Array)
            pairs.push(*result)
            pairs.push [sub_type.return_type, super_type.return_type]

            case
            when !super_type.block && !sub_type.block
              # No block required and given

            when super_type.block && sub_type.block
              match_params(name, super_type.block.type.params, sub_type.block.type.params, trace: trace).yield_self do |block_result|
                return block_result unless block_result.is_a?(Array)
                pairs.push(*block_result)
                pairs.push [super_type.block.type.return_type, sub_type.block.type.return_type]
              end

            else
              return failure(error: Result::Failure::BlockMismatchError.new(name: name),
                             trace: trace)
            end
          end
        end
      end

      def match_params(name, sub_params, super_params, trace:)
        pairs = []

        sub_flat = sub_params.flat_unnamed_params
        sup_flat = super_params.flat_unnamed_params

        failure = failure(error: Result::Failure::ParameterMismatchError.new(name: name),
                          trace: trace)

        case
        when super_params.rest
          return failure unless sub_params.rest

          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              pairs << [sub_type.last, super_params.rest]
            end
          end

          if sub_params.rest
            pairs << [sub_params.rest, super_params.rest]
          end

        when sub_params.rest
          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              break
            end
          end

          if sub_params.rest && !sup_flat.empty?
            sup_flat.each do |sup_type|
              pairs << [sub_params.rest, sup_type.last]
            end
          end
        when sub_params.required.size + sub_params.optional.size >= super_params.required.size + super_params.optional.size
          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              if sub_type.first == :required
                return failure
              else
                break
              end
            end
          end
        else
          return failure
        end

        sub_flat_kws = sub_params.flat_keywords
        sup_flat_kws = super_params.flat_keywords

        sup_flat_kws.each do |name, _|
          if sub_flat_kws.key?(name)
            pairs << [sub_flat_kws[name], sup_flat_kws[name]]
          else
            if sub_params.rest_keywords
              pairs << [sub_params.rest_keywords, sup_flat_kws[name]]
            else
              return failure
            end
          end
        end

        sub_params.required_keywords.each do |name, _|
          unless super_params.required_keywords.key?(name)
            return failure
          end
        end

        if sub_params.rest_keywords && super_params.rest_keywords
          pairs << [sub_params.rest_keywords, super_params.rest_keywords]
        end

        pairs
      end

      def check_block_params(name, sub_block, super_block, assumption:, trace:, constraints:)
        if sub_block && super_block
          check_method_params(name,
                              super_block.type.params,
                              sub_block.type.params,
                              assumption: assumption,
                              trace: trace,
                              constraints: constraints)
        else
          success(constraints: constraints)
        end
      end

      def check_block_return(sub_block, super_block, assumption:, trace:, constraints:)
        if sub_block && super_block
          relation = Relation.new(sub_type: super_block.type.return_type,
                                      super_type: sub_block.type.return_type)
          check(relation, assumption: assumption, trace: trace, constraints: constraints)
        else
          success(constraints: constraints)
        end
      end

      def expand_alias(type, &block)
        factory.expand_alias(type, &block)
      end
    end
  end
end
