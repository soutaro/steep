module Steep
  module AST
    module Builtin
      class Type
        attr_reader :module_name
        attr_reader :arity

        def initialize(module_name, arity: 0)
          @module_name = Names::Module.parse(module_name)
          @arity = arity
        end

        def instance_type(*args)
          arity == args.size or raise "Mulformed instance type: name=#{module_name}, args=#{args}"
          Types::Name::Instance.new(name: module_name, args: args)
        end

        def module_type
          Types::Name::Singleton.new(name: module_name)
        end

        def instance_type?(type, args: nil)
          if type.is_a?(Types::Name::Instance)
            if args
              arity == args.size or raise "Mulformed instance type: name=#{module_name}, args=#{args}"
              type.name == module_name && type.args == args
            else
              type.name == module_name && type.args.size == arity
            end
          else
            false
          end
        end

        def module_type?(type)
          if type.is_a?(Types::Name::Singleton)
            type.name == module_name
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

      def self.bottom_type
        AST::Types::Bot.new
      end

      def self.top_type
        AST::Types::Top.new
      end

      def self.optional(type)
        AST::Types::Union.build(types: [type, nil_type])
      end
    end
  end
end
