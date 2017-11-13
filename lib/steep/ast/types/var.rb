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

        def ==(other, ignore_location: false)
          other.is_a?(Var) &&
            other.name == name &&
            (ignore_location || !other.location || !location || other.location == location)
        end

        def hash
          self.class.hash ^ name.hash
        end

        def eql?(other)
          __send__(:==, other, ignore_location: true)
        end

        def self.fresh(name)
          @mutex ||= Mutex.new

          @mutex.synchronize do
            @max ||= 0
            @max += 1

            new(name: :"#{name}(#{@max})")
          end
        end

        def to_s
          "'#{name}"
        end

        def subst(s)
          if s.key?(name)
            s[name]
          else
            self
          end
        end
      end
    end
  end
end
