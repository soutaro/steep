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

        def ==(other, ignore_location: false)
          other.is_a?(Name) &&
            (ignore_location || !other.location || !location || other.location == location) &&
            other.name == name &&
            other.args == args
        end

        def hash
          self.class.hash ^ name.hash ^ args.hash
        end

        def eql?(other)
          __send__(:==, other, ignore_location: true)
        end

        def to_s
          if args.empty?
            "#{name}"
          else
            "#{name}<#{args.join(", ")}>"
          end
        end

        def self.new_module(location: nil, name:, args: [])
          new(location: location,
              name: TypeName::Module.new(name: name),
              args: args)
        end

        def self.new_class(location: nil, name:, constructor:, args: [])
          new(location: location,
              name: TypeName::Class.new(name: name, constructor: constructor),
              args: args)
        end

        def self.new_instance(location: nil, name:, args: [])
          new(location: location,
              name: TypeName::Instance.new(name: name),
              args: args)
        end

        def self.new_interface(location: nil, name:, args: [])
          new(location: location, name: TypeName::Interface.new(name: name), args: args)
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
            self.class.new_instance(location: location,
                                    name: name.name,
                                    args: args)
          else
            raise "Unknown name: #{name.inspect}"
          end
        end

        def class_type(constructor:)
          case name
          when TypeName::Instance
            self.class.new_class(location: location,
                                 name: name.name,
                                 constructor: constructor,
                                 args: args)
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
            self.class.new_module(location: location,
                                  name: name.name,
                                  args: args)
          when TypeName::Module
            self
          when TypeName::Class, TypeName::Interface
            raise "Cannot make module type: #{inspect}"
          else
            raise "Unknown name: #{name.inspect}"
          end
        end
      end
    end
  end
end
