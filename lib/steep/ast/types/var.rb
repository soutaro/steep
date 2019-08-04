module Steep
  module AST
    module Types
      class Var
        attr_reader :name
        attr_reader :location

        def initialize(name:, location: nil)
          @name = name
          @location = location
        end

        def ==(other)
          other.is_a?(Var) &&
            other.name == name
        end

        def hash
          self.class.hash ^ name.hash
        end

        alias eql? ==

        def self.fresh(name)
          @mutex ||= Mutex.new

          @mutex.synchronize do
            @max ||= 0
            @max += 1

            new(name: :"#{name}(#{@max})")
          end
        end

        def to_s
          name.to_s
        end

        def subst(s)
          if s.key?(name)
            s[name]
          else
            self
          end
        end

        def free_variables
          Set.new([name])
        end

        def level
          [0]
        end

        def with_location(new_location)
          self.class.new(name: name, location: new_location)
        end
      end
    end
  end
end
