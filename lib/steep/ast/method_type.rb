module Steep
  module AST
    class MethodType
      module Params
        class Base
          attr_reader :location

          def initialize(location:)
            @location = location
          end

          def update_location(location)
            dup.instance_eval do
              @location = location
              self
            end
          end
        end

        class Required < Base
          attr_reader :type
          attr_reader :next_params

          def initialize(location:, type:, next_params: nil)
            super(location: location)
            @type = type
            @next_params = next_params
          end
        end

        class Optional < Base
          attr_reader :type
          attr_reader :next_params

          def initialize(location:, type:, next_params: nil)
            super(location: location)
            @type = type
            @next_params = next_params
          end
        end

        class Rest < Base
          attr_reader :type
          attr_reader :next_params

          def initialize(location:, type:, next_params: nil)
            super(location: location)
            @type = type
            @next_params = next_params
          end
        end

        class RequiredKeyword < Base
          attr_reader :name
          attr_reader :type
          attr_reader :next_params

          def initialize(location:, name:, type:, next_params: nil)
            super(location: location)
            @name = name
            @type = type
            @next_params = next_params
          end
        end

        class OptionalKeyword < Base
          attr_reader :name
          attr_reader :type
          attr_reader :next_params

          def initialize(location:, name:, type:, next_params: nil)
            super(location: location)
            @name = name
            @type = type
            @next_params = next_params
          end
        end

        class RestKeyword < Base
          attr_reader :type

          def initialize(location:, type:)
            super(location: location)
            @type = type
          end
        end
      end

      class Block
        attr_reader :location
        attr_reader :params
        attr_reader :return_type
        attr_reader :optional

        def initialize(location:, params:, return_type:, optional:)
          @location = location
          @params = params
          @return_type = return_type
          @optional = optional
        end
      end

      attr_reader :location
      attr_reader :type_params
      attr_reader :params
      attr_reader :block
      attr_reader :return_type

      def initialize(location:, type_params:, params:, block:, return_type:)
        @location = location
        @type_params = type_params
        @params = params
        @block = block
        @return_type = return_type
      end
    end
  end
end
