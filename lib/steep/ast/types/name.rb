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

          def free_variables
            Set.new
          end

          def subst(s)
            self
          end

          def level
            [0]
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
            self.class.hash ^ name.hash ^ args.hash
          end

          def to_s
            if args.empty?
              "#{name}"
            else
              "#{name}[#{args.join(", ")}]"
            end
          end

          def with_location(new_location)
            self.class.new(name: name, args: args, location: new_location)
          end

          def subst(s)
            self.class.new(location: location,
                           name: name,
                           args: args.map {|a| a.subst(s) })
          end

          def free_variables
            args.each.with_object(Set.new) do |type, vars|
              vars.merge(type.free_variables)
            end
          end

          include Helper::ChildrenLevel

          def level
            [0] + level_of_children(args)
          end
        end

        class Class < Base
          attr_reader :constructor

          def initialize(name:, constructor:, location: nil)
            raise "Name should be a module name: #{name.inspect}" unless name.is_a?(Names::Module)
            super(name: name, location: location)
            @constructor = constructor
          end

          def ==(other)
            other.class == self.class &&
              other.name == name &&
              other.constructor == constructor
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash ^ constructor.hash
          end

          def to_s
            k = case constructor
                when true
                  " constructor"
                when false
                  " noconstructor"
                when nil
                  ""
                end
            "singleton(#{name.to_s})"
          end

          def with_location(new_location)
            self.class.new(name: name, constructor: constructor, location: new_location)
          end

          def to_instance(*args)
            Instance.new(name: name, args: args)
          end

          NOTHING = ::Object.new

          def updated(constructor: NOTHING)
            if NOTHING == constructor
              constructor = self.constructor
            end

            self.class.new(name: name, constructor: constructor, location: location)
          end
        end

        class Module < Base
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
        end

        class Instance < Applying
          def to_class(constructor:)
            Class.new(name: name, location: location, constructor: constructor)
          end

          def to_module
            Module.new(name: name, location: location)
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
