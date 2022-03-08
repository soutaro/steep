module Steep
  module AST
    module Types
      class Bot
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def ==(other)
          other.is_a?(Bot)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "bot"
        end

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [2]
        end

        def with_location(new_location)
          self.class.new(location: new_location)
        end
      end
    end
  end
end
