module Steep
  module Signature
    class Interface
      # @implements Steep__Signature__Interface
      # @type const Hash: Hash.class
      # @type const Interface: Steep__Signature__Interface.class
      # @type const Steep::Interface: Steep__Interface.class
      # @type const Steep::Interface::Method: Steep__Method.class

      # @dynamic name
      attr_reader :name
      # @dynamic params
      attr_reader :params
      # @dynamic methods
      attr_reader :methods

      def initialize(name:, params:, methods:)
        @name = name
        @params = params
        @methods = methods
      end

      def ==(other)
        # @type var other_: Steep__Signature__Interface
        other_ = other
        other_.is_a?(Interface) && other_.name == name && other_.params == params && other_.methods == methods
      end

      def to_interface(klass:, instance:, params:)
        raise "Invalid type application: expected: #{self.params.size}, actual: #{params.size}" if params.size != self.params.size

        # @type var map: Hash<Symbol, Steep__Type>
        map = Hash[self.params.zip(params)]
        Steep::Interface.new(name: name,
                             methods: methods.transform_values {|method|
                               types = method.map {|method_type|
                                 method_type.substitute(klass: klass, instance: instance, params: map)
                               }
                               Steep::Interface::Method.new(types: types, super_method: nil)
                             })
      end

      def validate(assignability)

      end
    end
  end
end
