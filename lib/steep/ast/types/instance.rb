module Steep
  module AST
    module Types
      class Instance
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def self.instance
          @instance ||= new()
        end

        def ==(other)
          other.is_a?(Instance)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          if s.instance_type
            s.instance_type
          else
            self
          end
        end

        @@fvs = Set[instance]
        def free_variables
          @@fvs
        end

        include Helper::NoChild

        def to_s
          "instance"
        end

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
