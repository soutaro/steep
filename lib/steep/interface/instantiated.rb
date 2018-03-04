module Steep
  module Interface
    class Instantiated
      attr_reader :type
      attr_reader :methods
      attr_reader :ivars

      def initialize(type:, methods:, ivars:)
        @type = type
        @methods = methods
        @ivars = ivars
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

      def validate(check)
        methods.each do |_, method|
          validate_method(check, method)
        end
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
          ivars: ivars
        )
      end
    end
  end
end
