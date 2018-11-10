module Steep
  module Interface
    class Abstract
      attr_reader :name
      attr_reader :kind
      attr_reader :params
      attr_reader :methods
      attr_reader :supers
      attr_reader :ivar_chains

      def initialize(name:, params:, methods:, supers:, ivar_chains:)
        @name = name
        @params = params
        @methods = methods
        @supers = supers
        @ivar_chains = ivar_chains
      end

      def ivars
        @ivars ||= ivar_chains.transform_values(&:type)
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
          ivar_chains: ivar_chains.transform_values {|chain| chain.subst(subst) }
        )
      end

      def without_private(option)
        if option
          self.class.new(
            name: name,
            params: params,
            methods: methods.reject {|_, method| method.private? },
            supers: supers,
            ivar_chains: ivar_chains
          )
        else
          self
        end
      end

      def without_initialize
        self.class.new(
          name: name,
          params: params,
          methods: methods.reject {|_, method| method.name == :initialize },
          supers: supers,
          ivar_chains: ivar_chains
        )
      end
    end
  end
end
