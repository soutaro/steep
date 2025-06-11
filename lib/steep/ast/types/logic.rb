module Steep
  module AST
    module Types
      module Logic
        class Base
          extend SharedInstance

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
        end

        class ReceiverIsNil < Base
        end

        class ReceiverIsNotNil < Base
        end

        class ReceiverIsArg < Base
        end

        class ArgIsReceiver < Base
        end

        class ArgEqualsReceiver < Base
        end

        class ArgIsAncestor < Base
        end

        class Guard < Base
          PATTERN = /\Aguard:\s*(self)\s+(is)\s+(.*?)\s*\Z/

          attr_reader :subject
          attr_reader :operator
          attr_reader :type

          def initialize(subject:, operator:, type:)
            @subject = subject
            @operator = operator
            @type = type
          end

          def ==(other)
            super && subject == other.subject && operator == other.operator && type == other.type
          end

          def hash
            self.class.hash ^ subject.hash ^ operator.hash ^ type.hash
          end
        end

        class Env < Base
          attr_reader :truthy, :falsy, :type

          def initialize(truthy:, falsy:, type:)
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
