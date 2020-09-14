module Steep
  module Interface
    class Interface
      class Entry
        attr_reader :method_types

        def initialize(method_types:)
          @method_types = method_types
        end

        def to_s
          "{ #{method_types.join(" || ")} }"
        end
      end

      attr_reader :type
      attr_reader :methods

      def initialize(type:, private:)
        @type = type
        @private = private
        @methods = {}
      end

      def private?
        @private
      end

      def public?
        !private?
      end
    end
  end
end
