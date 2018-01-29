module Steep
  module Subtyping
    class Check
      attr_reader :builder
      attr_reader :cache

      def initialize(builder:)
        @builder = builder
        @cache = {}
      end

      def check(constraint, assumption: Set.new, trace: Trace.new)
        prefix = trace.size
        cached = cache[constraint]
        if cached
          if cached.success?
            cached
          else
            cached.merge_trace(trace)
          end
        else
          if assumption.member?(constraint)
            success
          else
            trace.add(constraint.sub_type, constraint.super_type) do
              assumption = assumption + Set.new([constraint])
              check0(constraint, assumption: assumption, trace: trace).tap do |result|
                cache[constraint] = result.else do |failure|
                  failure.drop(prefix)
                end
              end
            end
          end
        end
      end

      def success
        Result::Success.new
      end

      def failure(error:, trace:)
        Result::Failure.new(error: error, trace: trace)
      end

      def check0(constraint, assumption:, trace:)
        case
        when same_type?(constraint, assumption: assumption)
          success

        when constraint.sub_type.is_a?(AST::Types::Any) || constraint.super_type.is_a?(AST::Types::Any)
          success

        when !constraint.sub_type.is_a?(AST::Types::Var) && constraint.super_type.is_a?(AST::Types::Var)
          success

        else
          begin
            sub_interface = resolve(constraint.sub_type)
            super_interface = resolve(constraint.super_type)

            check_interface(sub_interface, super_interface, assumption: assumption, trace: trace)

          rescue => exn
            STDERR.puts exn.inspect
            failure(error: Result::Failure::UnknownPairError.new(constraint: constraint),
                    trace: trace)
          end
        end
      end

      def same_type?(constraint, assumption:)
        case
        when constraint.sub_type == constraint.super_type
          true
        when constraint.sub_type.is_a?(AST::Types::Name) && constraint.super_type.is_a?(AST::Types::Name)
          return false unless constraint.sub_type.name == constraint.super_type.name
          return false unless constraint.sub_type.args.size == constraint.super_type.args.size
          constraint.sub_type.args.zip(constraint.super_type.args).all? do |(s, t)|
            assumption.include?(Constraint.new(sub_type: s, super_type: t)) &&
              assumption.include?(Constraint.new(sub_type: t, super_type: s))
          end
        else
          false
        end
      end

      def check_interface(sub_type, super_type, assumption:, trace:)
        super_type.methods.each do |name, sup_method|
          sub_method = sub_type.methods[name]

          if sub_method
            result = check_method(name, sub_method, sup_method, assumption: assumption, trace: trace)
            return result if result.failure?
          else
            return failure(error: Result::Failure::MethodMissingError.new(name: name),
                           trace: trace)
          end
        end

        success
      end

      def check_method(name, sub_method, super_method, assumption:, trace:)
        trace.add(sub_method, super_method) do
          all_results = super_method.types.map do |super_type|
            sub_method.types.map do |sub_type|
              super_args = super_type.type_params.map {|x| AST::Types::Var.fresh(x) }
              sub_args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }

              a = super_args.zip(sub_args).each.with_object(Set.new) do |(s, t), set|
                if s && t
                  set.add(Constraint.new(sub_type: s, super_type: t))
                  set.add(Constraint.new(sub_type: t, super_type: s))
                end
              end

              super_type = super_type.instantiate(Interface::Substitution.build(super_type.type_params,
                                                                                super_args))
              sub_type = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params,
                                                                            sub_args))

              trace.add(sub_type, super_type) do
                check_method_type(name,
                                  sub_type,
                                  super_type,
                                  assumption: assumption + a,
                                  trace: trace)
              end
            end
          end

          all_results.each do |results|
            if results.any?(&:success?)
              #ok
            else
              return results.find(&:failure?)
            end
          end

          success
        end
      end

      def check_method_type(name, sub_type, super_type, assumption:, trace:)
        check_method_params(name, sub_type.params, super_type.params, assumption: assumption, trace: trace).then do
          check_block_given(name, sub_type.block, super_type.block, trace: trace).then do
            check_block_params(name, sub_type.block, super_type.block, assumption: assumption, trace: trace).then do
              check_block_return(sub_type.block, super_type.block, assumption: assumption, trace: trace).then do
                constraint = Constraint.new(super_type: super_type.return_type,
                                            sub_type: sub_type.return_type)
                check(constraint, assumption: assumption, trace: trace)
              end
            end
          end
        end
      end

      def check_block_given(name, sub_block, super_block, trace:)
        case
        when !super_block && !sub_block
          success
        when super_block && sub_block
          success
        else
          failure(
            error: Result::Failure::BlockMismatchError.new(name: name),
            trace: trace
          )
        end
      end

      def check_method_params(name, sub_params, super_params, assumption:, trace:)
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

        pairs.each do |(sub_type, super_type)|
          constraint = Constraint.new(super_type: sub_type, sub_type: super_type)

          result = check(constraint, assumption: assumption, trace: trace)
          return result if result.failure?
        end

        success
      end

      def check_block_params(name, sub_block, super_block, assumption:, trace:)
        if sub_block
          check_method_params(name,
                              super_block.params,
                              sub_block.params,
                              assumption: assumption,
                              trace: trace)
        else
          success
        end
      end

      def check_block_return(sub_block, super_block, assumption:, trace:)
        if sub_block
          constraint = Constraint.new(sub_type: super_block.return_type,
                                      super_type: sub_block.return_type)
          check(constraint, assumption: assumption, trace: trace)
        else
          success
        end
      end

      def module_type(type)
        case
        when builder.signatures.class?(type.name)
          type.class_type(constructor: nil)
        when builder.signatures.module?(type.name)
          type.module_type
        end
      end

      def compact(types)
        types = types.reject {|type| type.is_a?(AST::Types::Any) }

        if types.empty?
          [AST::Types::Any.new]
        else
          compact0(types)
        end
      end

      def compact0(types)
        if types.size == 1
          types
        else
          type, *types_ = types
          compacted = compact0(types_)
          compacted.flat_map do |type_|
            case
            when type == type_
              [type]
            when check(Constraint.new(sub_type: type_, super_type: type)).success?
              [type]
            when check(Constraint.new(sub_type: type, super_type: type_)).success?
              [type_]
            else
              [type, type_]
            end
          end.uniq
        end
      end

      def resolve(type)
        case type
        when AST::Types::Any, AST::Types::Var, AST::Types::Class, AST::Types::Instance
          raise "Cannot resolve type to interface: #{type}"
        when AST::Types::Name
          builder.build(type.name).instantiate(
            type: type,
            args: type.args,
            instance_type: type.instance_type,
            module_type: module_type(type)
          )
        when AST::Types::Union
          interfaces = type.types.map do |type| resolve(type) end

          methods = interfaces.inject(nil) do |methods, i|
            if methods
              intersection = {}
              i.methods.each do |name, method|
                if methods.key?(name)
                  case
                  when method == methods[name]
                  when check_method(name, method, methods[name], assumption: Set.new, trace: Trace.new).success?
                    intersection[name] = methods[name]
                  when check_method(name, methods[name], method, assumption: Set.new, trace: Trace.new).success?
                    intersection[name] = method
                  else
                    intersection[name] = Interface::Method.new(
                      type_name: nil,
                      name: name,
                      types: methods[name].types + method.types,
                      super_method: nil,
                      attributes: []
                    )
                  end
                end
              end
              intersection
            else
              i.methods
            end
          end

          Interface::Instantiated.new(type: type, methods: methods)

        when AST::Types::Intersection
          interfaces = type.types.map do |type| resolve(type) end

          methods = interfaces.inject(nil) do |methods, i|
            if methods
              i.methods.each do |name, method|
                if methods.key?(name)
                  case
                  when method == methods[name]
                  when check_method(name, method, methods[name], assumption: Set.new, trace: Trace.new).success?
                    methods[name] = method
                  when check_method(name, methods[name], method, assumption: Set.new, trace: Trace.new).success?
                    methods[name] = methods[name]
                  else
                    methods[name] = Interface::Method.new(
                      type_name: nil,
                      name: name,
                      types: [],
                      super_method: nil,
                      attributes: []
                    )
                  end
                else
                  methods[name] = i.methods[name]
                end
              end
              methods
            else
              i.methods
            end
          end

          Interface::Instantiated.new(type: type, methods: methods)
        end
      end
    end
  end
end
