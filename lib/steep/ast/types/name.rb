module Steep
  module AST
    module Types
      module Name
        class Base
          attr_reader :location
          attr_reader :name

          def initialize(name:, location: nil)
            @location = location
            @name = name
          end

          include Helper::NoFreeVariables

          def subst(s)
            self
          end

          def level
            [0]
          end

          def map_type(&block)
            self
          end
        end

        class Applying < Base
          attr_reader :args

          def initialize(name:, args:, location: nil)
            super(name: name, location: location)
            @args = args
          end

          def ==(other)
            other.class == self.class &&
              other.name == name &&
              other.args == args
          end

          alias eql? ==

          def hash
            @hash ||= self.class.hash ^ name.hash ^ args.hash
          end

          def to_s
            if args.empty?
              "#{name}"
            else
              "#{name}[#{args.join(", ")}]"
            end
          end

          def with_location(new_location)
            _ = self.class.new(name: name, args: args, location: new_location)
          end

          def subst(s)
            if free_variables.intersect?(s.domain)
              _ = self.class.new(
                location: location,
                name: name,
                args: args.map {|a| a.subst(s) }
              )
            else
              self
            end
          end

          def free_variables
            @fvs ||= Set.new().tap do |set|
              args.each do |type|
                set.merge(type.free_variables)
              end
            end
          end

          def each_child(&block)
            if block
              args.each(&block)
            else
              args.each
            end
          end

          include Helper::ChildrenLevel

          def level
            [0] + level_of_children(args)
          end

          def map_type(&block)
            args = self.args.map(&block)

            _ = self.class.new(name: self.name, args: self.args, location: self.location)
          end
        end

        class Singleton < Base
          def ==(other)
            other.class == self.class &&
              other.name == name
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash
          end

          def to_s
            "singleton(#{name.to_s})"
          end

          def with_location(new_location)
            self.class.new(name: name, location: new_location)
          end

          include Helper::NoChild
        end

        class Instance < Applying
          def to_module
            Singleton.new(name: name, location: location)
          end
        end

        class Interface < Applying
        end

        class Alias < Applying
        end
      end
    end
  end
end
