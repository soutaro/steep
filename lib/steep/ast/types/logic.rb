module Steep
  module AST
    module Types
      module Logic
        class Base
          attr_reader :location

          def subst(s)
            self
          end

          def free_variables
            @fvs ||= Set[]
          end

          def hash
            self.class.hash
          end

          def ==(other)
            other.class == self.class
          end

          alias eql? ==

          def to_s
            "<% #{self.class} %>"
          end
        end

        class Not < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class ReceiverIsNil < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class ReceiverIsNotNil < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class ReceiverIsArg < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class ArgIsReceiver < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class Env < Base
          attr_reader :truthy, :falsy

          def initialize(truthy:, falsy:, location: nil)
            @truthy = truthy
            @falsy = falsy
          end

          def ==(other)
            other.is_a?(Env) && other.truthy == truthy && other.falsy == falsy
          end

          alias eql? ==

          def hash
            self.class.hash ^ truthy.hash ^ falsy.hash
          end
        end
      end
    end
  end
end
