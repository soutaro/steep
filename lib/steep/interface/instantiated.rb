module Steep
  module Interface
    class Instantiated
      attr_reader :type
      attr_reader :methods
      attr_reader :ivar_chains

      def initialize(type:, methods:, ivar_chains:)
        @type = type
        @methods = methods
        @ivar_chains = ivar_chains
      end

      def ivars
        @ivars ||= ivar_chains.transform_values(&:type)
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.params == params && other.methods == methods && other.ivars == ivars
      end

      class InvalidMethodOverrideError < StandardError
        attr_reader :type
        attr_reader :current_method
        attr_reader :super_method
        attr_reader :result

        def initialize(type:, current_method:, super_method:, result:)
          @type = type
          @current_method = current_method
          @super_method = super_method
          @result = result

          super "Invalid override of `#{current_method.name}` in #{type}: definition in #{current_method.type_name} is not compatible with its super (#{super_method.type_name})"
        end
      end

      class InvalidIvarOverrideError < StandardError
        attr_reader :type
        attr_reader :ivar_name
        attr_reader :current_ivar_type
        attr_reader :super_ivar_type

        def initialize(type:, ivar_name:, current_ivar_type:, super_ivar_type:)
          @type = type
          @ivar_name = ivar_name
          @current_ivar_type = current_ivar_type
          @super_ivar_type = super_ivar_type

          super "Invalid override of `#{ivar_name}` in #{type}: #{current_ivar_type} is not compatible with #{super_ivar_type}"
        end
      end

      def validate(check)
        methods.each do |_, method|
          validate_method(check, method)
        end

        ivar_chains.each do |name, chain|
          validate_chain(check, name, chain)
        end
      end

      def validate_chain(check, name, chain)
        return unless chain.parent

        this_type = chain.type
        super_type = chain.parent.type

        case
        when this_type.is_a?(AST::Types::Any) && super_type.is_a?(AST::Types::Any)
          # ok
        else
          relation = Subtyping::Relation.new(sub_type: this_type, super_type: super_type)

          result1 = check.check(relation, constraints: Subtyping::Constraints.empty)
          result2 = check.check(relation.flip, constraints: Subtyping::Constraints.empty)

          if result1.failure? || result2.failure? || this_type.is_a?(AST::Types::Any) || super_type.is_a?(AST::Types::Any)
            raise InvalidIvarOverrideError.new(type: self.type, ivar_name: name, current_ivar_type: this_type, super_ivar_type: super_type)
          end
        end

        validate_chain(check, name, chain.parent)
      end

      def validate_method(check, method)
        if method.super_method
          result = check.check_method(method.name,
                                      method,
                                      method.super_method,
                                      assumption: Set.new,
                                      trace: Subtyping::Trace.new,
                                      constraints: Subtyping::Constraints.empty)

          if result.success?
            validate_method(check, method.super_method)
          else
            raise InvalidMethodOverrideError.new(type: type,
                                                 current_method: method,
                                                 super_method: method.super_method,
                                                 result: result)
          end
        end
      end

      def select_method_type(&block)
        self.class.new(
          type: type,
          methods: methods.each.with_object({}) do |(name, method), methods|
            methods[name] = Method.new(
              type_name: method.type_name,
              name: method.name,
              types: method.types.select(&block),
              super_method: method.super_method,
              attributes: method.attributes,
            )
          end.reject do |_, method|
            method.types.empty?
          end,
          ivar_chains: ivar_chains
        )
      end
    end
  end
end
