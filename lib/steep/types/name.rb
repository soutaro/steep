module Steep
  module Types
    class Name
      # @implements Steep__Types__Name

      # @dynamic name
      attr_reader :name

      # @dynamic params
      attr_reader :params

      def initialize(name:, params:)
        @name = name
        @params = params
      end

      def self.interface(name:, params: [])
        self.new(name: TypeName::Interface.new(name: name), params: params)
      end

      def self.module(name:, params: [])
        self.new(name: TypeName::Module.new(name: name), params: params)
      end

      def self.instance(name:, params: [])
        self.new(name: TypeName::Instance.new(name: name), params: params)
      end

      def ==(other)
        other.is_a?(Name) && name == other.name && other.params == params
      end

      def hash
        name.hash ^ params.hash
      end

      def eql?(other)
        other == self
      end

      def closed?
        true
      end

      def substitute(klass:, instance:, params:)
        self.class.new(name: name, params: self.params.map {|t| t.substitute(klass: klass, instance: instance, params: params) })
      end

      def to_s
        "#{name}" + (params.empty? ? "" : "<#{params.map {|x| x.to_s }.join(", ")}>")
      end
    end
  end
end
