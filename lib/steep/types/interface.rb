module Steep
  module Types
    class Interface
      class Method
        attr_reader :param_types
        attr_reader :block
        attr_reader :return_type

        def initialize(param_types:, block:, return_type:)
          @param_types = param_types
          @block = block
          @return_type = return_type
        end
      end

      class Block
        attr_reader :param_types
        attr_reader :return_type

        def initialize(param_types:, return_type:)
          @param_types = param_types
          @return_type = return_type
        end
      end

      attr_reader :name
      attr_reader :methods

      def initialize(name:, methods:)
        @name = name
        @methods = methods
      end
    end
  end
end
