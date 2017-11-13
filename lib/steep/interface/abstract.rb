module Steep
  module Interface
    class Abstract
      attr_reader :name
      attr_reader :kind
      attr_reader :params
      attr_reader :methods
      attr_reader :constraints

      def initialize(name:, params:, methods:, constraints:)
        @name = name
        @params = params
        @methods = methods
        @constraints = constraints
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.type == type &&
          other.params == params &&
          other.methods == methods &&
          other.constraints == constraints
      end

      def instantiate(type:, args:, instance_type:, module_type:)
        subst = Substitution.build(params, args, instance_type: instance_type, module_type: module_type)

        Instantiated.new(
          type: type,
          methods: methods.transform_values {|method| method.subst(subst) }
        )
      end
    end
  end
end
