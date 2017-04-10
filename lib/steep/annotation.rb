module Steep
  module Annotation
    class Base; end

    class VarType < Base
      attr_reader :var
      attr_reader :type

      def initialize(var:, type:)
        @var = var
        @type = type
      end

      def ==(other)
        other.is_a?(VarType) &&
          other.var == var &&
          other.type == type
      end
    end

    class MethodType < Base
      attr_reader :method
      attr_reader :type

      def initialize(method:, type:)
        @method = method
        @type = type
      end

      def ==(other)
        other.is_a?(MethodType) &&
          other.method == method &&
          other.type == type
      end
    end
  end
end
