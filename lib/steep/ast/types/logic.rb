module Steep
  module AST
    module Types
      module Logic
        class Base
          attr_reader :location

          def subst(s)
            self
          end

          include Helper::NoFreeVariables

          include Helper::NoChild

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

          def level
            [0]
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

        class ArgEqualsReceiver < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class ArgIsAncestor < Base
          def initialize(location: nil)
            @location = location
          end
        end

        class Env < Base
          attr_reader :truthy, :falsy, :type

          def initialize(truthy:, falsy:, type:, location: nil)
            @truthy = truthy
            @falsy = falsy
            @type = type
          end

          def ==(other)
            other.is_a?(Env) && other.truthy == truthy && other.falsy == falsy && other.type == type
          end

          alias eql? ==

          def hash
            self.class.hash ^ truthy.hash ^ falsy.hash
          end

          def inspect
            "#<Steep::AST::Types::Env @type=#{type}, @truthy=..., @falsy=...>"
          end

          alias to_s inspect
        end
      end
    end
  end
end
