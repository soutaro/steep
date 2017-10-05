module Steep
  module TypeName
    class Base
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name
      end

      def hash
        name.hash
      end

      def eql?(other)
        self == other
      end

      def to_s
        name.to_s
      end
    end

    class Interface < Base; end

    class Module < Base
      attr_reader :constructor

      def to_s
        k = case constructor
            when nil
              ""
            when true
              " constructor"
            when false
              " noconstructor"
            end

        "#{name}.module#{k}"
      end

      def initialize(name:, constructor:)
        super(name: name)
        @constructor = constructor
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name && other.constructor == constructor
      end
    end

    class Instance < Base; end
  end
end
