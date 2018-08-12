module Steep
  module AST
    module Builtin
      class Type
        attr_reader :module_name
        attr_reader :arity

        def initialize(module_name, arity: 0)
          @module_name = ModuleName.parse(module_name)
          @arity = arity
        end

        def instance_type(*args)
          arity == args.size or raise "Mulformed instance type: name=#{module_name}, args=#{args}"
          Types::Name.new(name: TypeName::Instance.new(name: module_name),
                          args: args)
        end

        def class_type(constructor: nil)
          Types::Name.new(name: TypeName::Class.new(name: module_name, constructor: constructor),
                          args: [])
        end

        def module_type
          Types::Name.new(name: TypeName::Module.new(name: module_name), args: [])
        end

        def instance_type?(type, args: nil)
          if type.is_a?(Types::Name) && type.name.is_a?(TypeName::Instance)
            if args
              arity == args.size or raise "Mulformed instance type: name=#{module_name}, args=#{args}"
              type.name.name == module_name && type.args == args
            else
              type.name.name == module_name && type.args.size == arity
            end
          else
            false
          end
        end

        NONE = ::Object.new

        def class_type?(type, constructor: NONE)
          if type.is_a?(Types::Name) && type.name.is_a?(TypeName::Class)
            unless constructor.equal?(NONE)
              type.name.name == module_name && type.name.constructor == constructor
            else
              type.name.name == module_name
            end
          else
            false
          end
        end

        def module_type?(type)
          if type.is_a?(Types::Name) && type.name.is_a?(TypeName::Module)
            type.name.name == module_name
          else
            false
          end
        end
      end

      Object = Type.new("::Object")
      BasicObject = Type.new("::BasicObject")
      Array = Type.new("::Array", arity: 1)
      Range = Type.new("::Range", arity: 1)
      Hash = Type.new("::Hash", arity: 2)
      Module = Type.new("::Module")
      Class = Type.new("::Class")
      Integer = Type.new("::Integer")
      Float = Type.new("::Float")
      String = Type.new("::String")
      Symbol = Type.new("::Symbol")
      TrueClass = Type.new("::TrueClass")
      FalseClass = Type.new("::FalseClass")
      Regexp = Type.new("::Regexp")
      NilClass = Type.new("::NilClass")
      Proc = Type.new("::Proc")

      def self.nil_type
        AST::Types::Nil.new
      end

      def self.any_type
        AST::Types::Any.new
      end

      def self.bool_type
        AST::Types::Boolean.new
      end

      def self.optional(type)
        AST::Types::Union.build(types: [type, nil_type])
      end
    end
  end
end
