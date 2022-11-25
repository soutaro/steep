module Steep
  module AST
    module Types
      class Class
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def self.instance
          @instance ||= new()
        end

        def to_s
          "class"
        end

        def ==(other)
          other.is_a?(Class)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          if s.module_type
            s.module_type
          else
            self
          end
        end

        @@fvs = Set[instance]

        def free_variables
          @@fvs
        end

        include Helper::NoChild

        def level
          [0]
        end

        def with_location(new_location)
          self.class.new(location: new_location)
        end
      end
    end
  end
end
