module Steep
  module Types
    class Tuple
      # @implements Steep__Types__Name
      # @type const TypeName::Interface: Steep__TypeName.class
      # @type const TypeName::Module: Steep__TypeName.class
      # @type const TypeName::Instance: Steep__TypeName.class

      # @dynamic types
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def self.interface(types: [])
        self.new(types: types)
      end

      def self.module(types: [])
        self.new(types: types)
      end

      def self.instance(types: [])
        self.new(types: types)
      end

      def ==(other)
        other.is_a?(Tuple) && other.types == types
      end

      def hash
        types.hash
      end

      def eql?(other)
        other == self
      end

      def closed?
        true
      end

      def substitute(klass:, instance:, params:)
        self.class.new(types: self.types.map {|t| t.substitute(klass: klass, instance: instance, params: params) })
      end

      def to_s
        "[#{ types.map {|x| x.to_s }.join(", ") }]"
      end
    end
  end
end
