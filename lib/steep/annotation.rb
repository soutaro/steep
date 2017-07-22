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

    class Collection
      attr_reader :var_types
      attr_reader :method_types
      attr_reader :annotations

      def initialize(annotations:)
        @var_types = {}
        @method_types = {}

        annotations.each do |annotation|
          case annotation
          when VarType
            var_types[annotation.var] = annotation
          when MethodType
            method_types[annotation.method] = annotation
          else
            raise "Unexpected annotation: #{annotation.inspect}"
          end
        end

        @annotations = annotations
      end

      def lookup_var_type(name)
        var_types[name]&.type
      end

      def lookup_method_type(name)
        method_types[name]
      end

      def +(other)
        self.class.new(annotations: annotations + other.annotations)
      end
    end
  end
end
