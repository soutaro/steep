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
        self.class.hash ^ name.hash
      end

      alias eql? ==

      def to_s
        name.to_s
      end
    end

    class Interface < Base; end

    class Class < Base
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

        "#{name}.class#{k}"
      end

      def initialize(name:, constructor:)
        super(name: name)
        @constructor = constructor
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name && other.constructor == constructor
      end

      def hash
        self.class.hash ^ name.hash ^ constructor.hash
      end

      NOTHING = Object.new

      def updated(constructor: NOTHING)
        if NOTHING == constructor
          constructor = self.constructor
        end

        self.class.new(name: name, constructor: constructor)
      end
    end

    class Module < Base
      def to_s
        "#{name}.module"
      end
    end

    class Instance < Base; end
  end
end
