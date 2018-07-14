module Steep
  module Interface
    class Method
      attr_reader :type_name
      attr_reader :name
      attr_reader :super_method
      attr_reader :types
      attr_reader :attributes

      def initialize(type_name:, name:, types:, super_method:, attributes:)
        @type_name = type_name
        @name = name
        @types = types
        @super_method = super_method
        @attributes = attributes
      end

      def ==(other)
        other.is_a?(Method) &&
          other.type_name == type_name &&
          other.name == name &&
          other.types == types &&
          other.super_method == super_method &&
          other.attributes == attributes
      end

      def incompatible?
        attributes.include?(:incompatible)
      end

      def closed?
        types.all?(&:closed?)
      end

      def subst(s)
        self.class.new(
          type_name: type_name,
          name: name,
          types: types.map {|type| type.subst(s) },
          super_method: super_method&.subst(s),
          attributes: attributes
        )
      end

      def with_super(super_method)
        self.class.new(
          type_name: type_name,
          name: name,
          types: types,
          super_method: super_method,
          attributes: attributes
        )
      end

      def with_types(types)
        self.class.new(
          type_name: type_name,
          name: name,
          types: types,
          super_method: super_method,
          attributes: attributes
        )
      end

      def include_in_chain?(method)
        (method.type_name == type_name &&
          method.name == name &&
          method.types == types &&
          method.attributes == attributes) ||
          super_method&.include_in_chain?(method)
      end
    end
  end
end
