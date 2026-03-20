module Steep
  module Diagnostic
    module Signature
      class Base
        include Helper

        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def header_line
          raise
        end

        def detail_lines
          nil
        end

        def diagnostic_code
          "RBS::#{error_name}"
        end

        def path
          if location
            Pathname(location.buffer.name)
          end
        end
      end

      class SyntaxError < Base
        attr_reader :exception

        def initialize(exception, location:)
          super(location: location)
          @exception = exception
        end

        def self.parser_syntax_error_message(exception)
          string = exception.location.source.to_s
          unless string.empty?
            string = " (#{string})"
          end

          "Syntax error caused by token `#{exception.token_type}`#{string}"
        end

        def header_line
          exception.message
        end
      end

      class DuplicatedDeclaration < Base
        attr_reader :type_name

        def initialize(type_name:, location:)
          super(location: location)
          @type_name = type_name
        end

        def header_line
          "Declaration of `#{type_name}` is duplicated"
        end
      end

      class UnknownTypeName < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Cannot find type `#{name}`"
        end
      end

      class InvalidTypeApplication < Base
        attr_reader :name
        attr_reader :args
        attr_reader :params

        def initialize(name:, args:, params:, location:)
          super(location: location)
          @name = name
          @args = args
          @params = params
        end

        def header_line
          case
          when params.empty?
            "Type `#{name}` is not generic but used as a generic type with #{args.size} arguments"
          when args.empty?
            "Type `#{name}` is generic but used as a non generic type"
          else
            "Type `#{name}` expects #{params.size} arguments, but #{args.size} arguments are given"
          end
        end
      end

      class UnsatisfiableTypeApplication < Base
        attr_reader :type_name
        attr_reader :type_arg
        attr_reader :type_param
        attr_reader :result

        include ResultPrinter2

        def initialize(type_name:, type_arg:, type_param:, result:, location:)
          super(location: location)
          @type_name = type_name
          @type_arg = type_arg
          @type_param = type_param
          @result = result
        end

        def header_line
          "Type application of `#{type_name}` doesn't satisfy the constraints: #{type_arg} <: #{type_param.upper_bound}"
        end
      end

      class InvalidMethodOverload < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Cannot find a non-overloading definition of `#{method_name}` in `#{class_name}`"
        end
      end

      class UnknownMethodAlias < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Cannot find the original method `#{method_name}` in `#{class_name}`"
        end
      end

      class DuplicatedMethodDefinition < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Non-overloading method definition of `#{method_name}` in `#{class_name}` cannot be duplicated"
        end
      end

      class RecursiveAlias < Base
        attr_reader :class_name
        attr_reader :names

        def initialize(class_name:, names:, location:)
          super(location: location)
          @class_name = class_name
          @names = names
        end

        def header_line
          "Circular method alias is detected in `#{class_name}`: #{names.join(" -> ")}"
        end
      end

      class RecursiveAncestor < Base
        attr_reader :ancestors

        def initialize(ancestors:, location:)
          super(location: location)
          @ancestors = ancestors
        end

        def header_line
          names = ancestors.map do |ancestor|
            case ancestor
            when RBS::Definition::Ancestor::Singleton
              "singleton(#{ancestor.name})"
            when RBS::Definition::Ancestor::Instance
              if ancestor.args.empty?
                ancestor.name.to_s
              else
                "#{ancestor.name}[#{ancestor.args.join(", ")}]"
              end
            end
          end

          "Circular inheritance/mix-in is detected: #{names.join(" <: ")}"
        end
      end

      class SuperclassMismatch < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Different superclasses are specified for `#{name}`"
        end
      end

      class GenericParameterMismatch < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Different generic parameters are specified across definitions of `#{name}`"
        end
      end

      class InvalidVarianceAnnotation < Base
        attr_reader :name
        attr_reader :param

        def initialize(name:, param:, location:)
          super(location: location)
          @name = name
          @param = param
        end

        def header_line
          "The variance of type parameter `#{param.name}` is #{param.variance}, but used in incompatible position here"
        end
      end

      class ModuleSelfTypeError < Base
        attr_reader :name
        attr_reader :ancestor
        attr_reader :result

        include ResultPrinter2

        def initialize(name:, ancestor:, result:, location:)
          super(location: location)

          @name = name
          @ancestor = ancestor
          @result = result
        end

        def relation
          result.relation
        end

        def header_line
          "Module self type constraint in type `#{name}` doesn't satisfy: `#{relation}`"
        end
      end

      class VariableDuplicationError < Base
        attr_reader :type_name
        attr_reader :variable_name

        def initialize(type_name:, variable_name:, location:)
          @type_name = type_name
          @variable_name = variable_name
          @location = location
        end
      end

      class InstanceVariableDuplicationError < VariableDuplicationError
        def header_line
          "Duplicated instance variable name `#{variable_name}` in `#{type_name}`"
        end
      end

      class ClassInstanceVariableDuplicationError < VariableDuplicationError
        def header_line
          "Duplicated class instance variable name `#{variable_name}` in `#{type_name}`"
        end
      end

      class ClassVariableDuplicationError < Base
        attr_reader :class_name
        attr_reader :other_class_name
        attr_reader :variable_name

        def initialize(class_name:, other_class_name:, variable_name:, location:)
          super(location: location)

          @class_name = class_name
          @other_class_name = other_class_name
          @variable_name = variable_name
        end

        def header_line
          "Class variable definition `#{variable_name}` in `#{class_name}` may be overtaken by `#{other_class_name}`"
        end
      end

      class InstanceVariableTypeError < Base
        attr_reader :name
        attr_reader :var_type
        attr_reader :parent_type

        def initialize(name:, location:, var_type:, parent_type:)
          super(location: location)

          @name = name
          @var_type = var_type
          @parent_type = parent_type
        end

        def header_line
          "Instance variable cannot have different type with parents: #{var_type} <=> #{parent_type}"
        end
      end

      class MixinClassError < Base
        attr_reader :member
        attr_reader :type_name

        def initialize(location:, member:, type_name:)
          super(location: location)
          @member = member
          @type_name = type_name
        end

        def header_line
          member_name = case member
                        when RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend
                          member.name
                        when RBS::AST::Ruby::Members::IncludeMember, RBS::AST::Ruby::Members::ExtendMember, RBS::AST::Ruby::Members::PrependMember
                          member.module_name
                        end
          "Cannot #{mixin_name} a class `#{member_name}` in the definition of `#{type_name}`"
        end

        private

        def mixin_name
          case mem = member
          when RBS::AST::Members::Prepend, RBS::AST::Ruby::Members::PrependMember
            "prepend"
          when RBS::AST::Members::Include, RBS::AST::Ruby::Members::IncludeMember
            "include"
          when RBS::AST::Members::Extend, RBS::AST::Ruby::Members::ExtendMember
            "extend"
          else
            raise "Unknown mixin type: #{mem.class}"
          end
        end
      end

      class InheritModuleError < Base
        attr_reader :super_class

        def initialize(super_class)
          super(location: super_class.location)
          @super_class = super_class
        end

        def header_line
          "Cannot inherit from a module `#{super_class.name}`"
        end
      end

      class UnexpectedError < Base
        attr_reader :message

        def initialize(message:, location:)
          @message = message
          @location = location
        end

        def header_line
          "Unexpected error: #{message}"
        end
      end

      class RecursiveTypeAlias < Base
        attr_reader :alias_names

        def initialize(alias_names:, location:)
          @alias_names = alias_names
          super(location: location)
        end

        def header_line
          "Type aliases cannot be *directly recursive*: #{alias_names.join(", ")}"
        end
      end

      class NonregularTypeAlias < Base
        attr_reader :type_name
        attr_reader :nonregular_type

        def initialize(type_name:, nonregular_type:, location:)
          @type_name = type_name
          @nonregular_type = nonregular_type
          @location = location
        end

        def header_line
          "Type alias #{type_name} is defined *non-regular*: #{nonregular_type}"
        end
      end

      class InconsistentClassModuleAliasError < Base
        attr_reader :decl

        def initialize(decl:)
          @decl = decl
          super(location: decl.location&.[](:old_name))
        end

        def header_line
          expected_kind =
            case decl
            when RBS::AST::Declarations::ModuleAlias
              "module"
            when RBS::AST::Declarations::ClassAlias
              "class"
            when RBS::AST::Ruby::Declarations::ClassModuleAliasDecl
              if decl.annotation.is_a?(RBS::AST::Ruby::Annotations::ClassAliasAnnotation)
                "class"
              else
                "module"
              end
            end

          "A #{expected_kind} `#{decl.new_name}` cannot be an alias of `#{decl.old_name}`"
        end
      end

      class CyclicClassAliasDefinitionError < Base
        attr_reader :decl

        def initialize(decl:)
          @decl = decl
          super(location: decl.location&.[](:new_name))
        end

        def header_line
          "#{decl.new_name} is a cyclic definition"
        end
      end

      class TypeParamDefaultReferenceError < Base
        attr_reader :type_param

        def initialize(type_param, location:)
          super(location: location)
          @type_param = type_param
        end

        def header_line
          "The default type of `#{type_param.name}` cannot depend on optional type parameters"
        end
      end

      class UnsatisfiableGenericsDefaultType < Base
        attr_reader :param_name, :result

        include ResultPrinter2

        def initialize(param_name, result, location:)
          super(location: location)
          @param_name = param_name
          @result = result
        end

        def relation
          result.relation
        end

        def header_line
          "The default type of `#{param_name}` doesn't satisfy upper bound constraint: #{relation}"
        end
      end

      class DeprecatedTypeName < Base
        attr_reader :type_name
        attr_reader :message

        def initialize(type_name, message, location:)
          super(location: location)
          @type_name = type_name
          @message = message
        end

        def header_line
          buffer = "Type `#{type_name}` is deprecated"
          if message
            buffer = +buffer
            buffer << ": " << message
          end
          buffer
        end
      end

      class InlineDiagnostic < Base
        attr_reader :diagnostic

        def initialize(diagnostic)
          super(location: diagnostic.location)
          @diagnostic = diagnostic
        end

        def header_line
          diagnostic.message
        end
      end

      def self.from_rbs_error(error, factory:)
        case error
        when RBS::ParsingError
          Diagnostic::Signature::SyntaxError.new(error, location: error.location)
        when RBS::DuplicatedDeclarationError
          Diagnostic::Signature::DuplicatedDeclaration.new(
            type_name: error.name,
            location: error.decls.fetch(0).location
          )
        when RBS::GenericParameterMismatchError
          Diagnostic::Signature::GenericParameterMismatch.new(
            name: error.name,
            location: error.decl.location
          )
        when RBS::InvalidTypeApplicationError
          Diagnostic::Signature::InvalidTypeApplication.new(
            name: error.type_name,
            args: error.args.map {|ty| factory.type(ty) },
            params: error.params,
            location: error.location
          )
        when RBS::NoTypeFoundError,
          RBS::NoSuperclassFoundError,
          RBS::NoMixinFoundError,
          RBS::NoSelfTypeFoundError
          Diagnostic::Signature::UnknownTypeName.new(
            name: error.type_name,
            location: error.location
          )
        when RBS::InvalidOverloadMethodError
          Diagnostic::Signature::InvalidMethodOverload.new(
            class_name: error.type_name,
            method_name: error.method_name,
            location: error.members.fetch(0).location
          )
        when RBS::DuplicatedMethodDefinitionError
          Diagnostic::Signature::DuplicatedMethodDefinition.new(
            class_name: error.type_name,
            method_name: error.method_name,
            location: error.location
          )
        when RBS::DuplicatedInterfaceMethodDefinitionError
          Diagnostic::Signature::DuplicatedMethodDefinition.new(
            class_name: error.type_name,
            method_name: error.method_name,
            location: error.member.location
          )
        when RBS::UnknownMethodAliasError
          Diagnostic::Signature::UnknownMethodAlias.new(
            class_name: error.type_name,
            method_name: error.original_name,
            location: error.location
          )
        when RBS::RecursiveAliasDefinitionError
          Diagnostic::Signature::RecursiveAlias.new(
            class_name: error.type.name,
            names: error.defs.map(&:name),
            location: error.defs.fetch(0).original&.location
          )
        when RBS::RecursiveAncestorError
          Diagnostic::Signature::RecursiveAncestor.new(
            ancestors: error.ancestors,
            location: error.location
          )
        when RBS::SuperclassMismatchError
          # Try to find a declaration in a user file (not in core/stdlib)
          # If the type is reopened in user code, use that location instead of the core library location
          location = error.entry.primary_decl.location
          
          # Check if there are other declarations in non-core files
          # context_decls is an array of [context, decl] pairs
          error.entry.context_decls.each do |context, decl|
            decl_location = decl.location
            if decl_location
              buffer_name = decl_location.buffer.name.to_s
              # Prefer locations that are not in core/stdlib (gems directory)
              unless buffer_name.include?('/gems/') || buffer_name.include?('/core/') || buffer_name.include?('/stdlib/')
                location = decl_location
                break
              end
            end
          end
          
          Diagnostic::Signature::SuperclassMismatch.new(
            name: error.name,
            location: location
          )
        when RBS::InvalidVarianceAnnotationError
          Diagnostic::Signature::InvalidVarianceAnnotation.new(
            name: error.type_name,
            param: error.param,
            location: error.location
          )
        when RBS::MixinClassError
          Diagnostic::Signature::MixinClassError.new(
            location: error.location,
            type_name: error.type_name,
            member: error.member,
          )
        when RBS::RecursiveTypeAliasError
          Diagnostic::Signature::RecursiveTypeAlias.new(
            alias_names: error.alias_names,
            location: error.location
          )
        when RBS::NonregularTypeAliasError
          Diagnostic::Signature::NonregularTypeAlias.new(
            type_name: error.diagnostic.type_name,
            nonregular_type: factory.type(error.diagnostic.nonregular_type),
            location: error.location
          )
        when RBS::InheritModuleError
          Diagnostic::Signature::InheritModuleError.new(error.super_decl)
        when RBS::InconsistentClassModuleAliasError
          Diagnostic::Signature::InconsistentClassModuleAliasError.new(decl: error.alias_entry.decl)
        when RBS::CyclicClassAliasDefinitionError
          Diagnostic::Signature::CyclicClassAliasDefinitionError.new(decl: error.alias_entry.decl)
        when RBS::TypeParamDefaultReferenceError
          Diagnostic::Signature::TypeParamDefaultReferenceError.new(error.type_param, location: error.location)
        when RBS::InstanceVariableDuplicationError
          Diagnostic::Signature::InstanceVariableDuplicationError.new(type_name: error.type_name, variable_name: error.variable_name, location: error.location)
        when RBS::ClassInstanceVariableDuplicationError
          Diagnostic::Signature::ClassInstanceVariableDuplicationError.new(type_name: error.type_name, variable_name: error.variable_name, location: error.location)
        else
          raise error
        end
      end
    end
  end
end
