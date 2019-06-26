module Steep
  module AST
    module Types
      class Factory
        attr_reader :definition_builder

        def initialize(builder:)
          @definition_builder = builder
        end

        def type(type)
          case type
          when Ruby::Signature::Types::Bases::Any
            Any.new(location: nil)
          when Ruby::Signature::Types::Bases::Class
            Class.new(location: nil)
          when Ruby::Signature::Types::Bases::Instance
            Instance.new(location: nil)
          when Ruby::Signature::Types::Bases::Self
            Self.new(location: nil)
          when Ruby::Signature::Types::Bases::Top
            Top.new(location: nil)
          when Ruby::Signature::Types::Bases::Bottom
            Bot.new(location: nil)
          when Ruby::Signature::Types::Bases::Bool
            Boolean.new(location: nil)
          when Ruby::Signature::Types::Bases::Void
            Void.new(location: nil)
          when Ruby::Signature::Types::Bases::Nil
            Nil.new(location: nil)
          when Ruby::Signature::Types::Variable
            Var.new(name: type.name, location: nil)
          when Ruby::Signature::Types::ClassSingleton
            type_name = type_name(type.name)
            Name::Class.new(name: type_name, location: nil, constructor: nil)
          when Ruby::Signature::Types::ClassInstance
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Instance.new(name: type_name, args: args, location: nil)
          when Ruby::Signature::Types::Interface
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Interface.new(name: type_name, args: args, location: nil)
          when Ruby::Signature::Types::Alias
            type_name = type_name(type.name)
            Name::Alias.new(name: type_name, args: [], location: nil)
          when Ruby::Signature::Types::Union
            Union.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Intersection
            Intersection.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Optional
            Union.build(types: [type(type.type), Nil.new(location: nil)], location: nil)
          when Ruby::Signature::Types::Literal
            Literal.new(value: type.literal, location: nil)
          when Ruby::Signature::Types::Tuple
            Tuple.new(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Record
            elements = type.fields.each.with_object({}) do |(key, value), hash|
              hash[key] = type(value)
            end
            Record.new(elements: elements, location: nil)
          when Ruby::Signature::Types::Proc
            params = params(type.type)
            return_type = type(type.type.return_type)
            Proc.new(params: params, return_type: return_type, location: nil)
          else
            raise "Unexpected type given: #{type}"
          end
        end

        def type_name(name)
          case
          when name.class?
            Names::Module.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          when name.interface?
            Names::Interface.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          when name.alias?
            Names::Alias.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          end
        end

        def namespace(namespace)
          Namespace.parse(namespace.to_s)
        end

        def params(type)
          Interface::Params.new(
            required: type.required_positionals.map {|param| type(param.type) },
            optional: type.optional_positionals.map {|param| type(param.type) },
            rest: type.rest_positionals&.yield_self {|param| type(param.type) },
            required_keywords: type.required_keywords.transform_values {|param| type(param.type) },
            optional_keywords: type.optional_keywords.transform_values {|param| type(param.type) },
            rest_keywords: type.rest_keywords&.yield_self {|param| type(param.type) }
          )
        end
      end
    end
  end
end
