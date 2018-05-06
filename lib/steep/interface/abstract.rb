module Steep
  module Interface
    class Abstract
      attr_reader :name
      attr_reader :kind
      attr_reader :params
      attr_reader :methods
      attr_reader :supers
      attr_reader :ivars

      def initialize(name:, params:, methods:, supers:, ivars:)
        @name = name
        @params = params
        @methods = methods
        @supers = supers
        @ivars = ivars
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.name == name &&
          other.params == params &&
          other.methods == methods &&
          other.supers == supers &&
          other.ivars == ivars
      end

      def instantiate(type:, args:, instance_type:, module_type:)
        Steep.logger.debug("type=#{type}, self=#{name}, args=#{args}, params=#{params}")
        subst = Substitution.build(params, args, instance_type: instance_type, module_type: module_type, self_type: type)

        Instantiated.new(
          type: type,
          methods: methods.transform_values {|method| method.subst(subst) },
          ivars: ivars.transform_values {|type| type.subst(subst) }
        )
      end
    end
  end
end
