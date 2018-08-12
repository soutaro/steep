module Steep
  module AST
    module Types
      class Name
        attr_reader :location
        attr_reader :name
        attr_reader :args

        def initialize(name:, args:, location: nil)
          @location = location
          @name = name
          @args = args
        end

        def ==(other)
          other.is_a?(Name) &&
            other.name == name &&
            other.args == args
        end

        def hash
          self.class.hash ^ name.hash ^ args.hash
        end

        alias eql? ==

        def to_s
          if args.empty?
            "#{name}"
          else
            "#{name}<#{args.join(", ")}>"
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

        def instance_type
          case name
          when TypeName::Interface, TypeName::Instance
            self
          when TypeName::Module, TypeName::Class
            self.class.new(name: TypeName::Instance.new(name: name.name),
                           location: location,
                           args: [])
          else
            raise "Unknown name: #{name.inspect}"
          end
        end

        def class_type(constructor:)
          case name
          when TypeName::Instance
            self.class.new(name: TypeName::Class.new(name: name.name, constructor: constructor),
                           args: [])
          when TypeName::Class
            self
          when TypeName::Module, TypeName::Interface
            raise "Cannot make class type: #{inspect}"
          else
            raise "Unknown name: #{name.inspect}"
          end
        end

        def module_type
          case name
          when TypeName::Instance,
            self.class.new(name: TypeName::ModuleName.new(name: name.name))
          when TypeName::Module
            self
          when TypeName::Class, TypeName::Interface
            raise "Cannot make module type: #{inspect}"
          else
            raise "Unknown name: #{name.inspect}"
          end
        end

        def free_variables
          self.args.each.with_object(Set.new) do |type, vars|
            vars.merge(type.free_variables)
          end
        end

        include Helper::ChildrenLevel

        def level
          [0] + level_of_children(args)
        end
      end
    end
  end
end
