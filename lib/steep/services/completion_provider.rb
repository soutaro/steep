module Steep
  module Services
    module CompletionProvider
      Position = _ = Struct.new(:line, :column, keyword_init: true) do
        # @implements Position
        def -(size)
          Position.new(line: line, column: column - size)
        end
      end

      Range = _ = Struct.new(:start, :end, keyword_init: true)

      InstanceVariableItem = _ = Struct.new(:identifier, :range, :type, keyword_init: true)
      KeywordArgumentItem = _ = Struct.new(:identifier, :range, keyword_init: true)
      LocalVariableItem = _ = Struct.new(:identifier, :range, :type, keyword_init: true)
      ConstantItem = _ = Struct.new(:env, :identifier, :range, :type, :full_name, keyword_init: true) do
        # @implements ConstantItem

        def class?
          env.class_entry(full_name) ? true : false
        end

        def module?
          env.module_entry(full_name) ? true : false
        end

        def comments
          case entry = env.constant_entry(full_name)
          when ::RBS::Environment::ConstantEntry
            [entry.decl.comment]
          when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
            entry.each_decl.map do |decl|
              case decl
              when ::RBS::AST::Declarations::Base
                decl.comment
              when ::RBS::AST::Ruby::Declarations::Base
                nil
              end
            end
          when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
            [entry.decl.comment]
          else
            raise
          end
        end

        def decl
          case entry = env.constant_entry(full_name)
          when ::RBS::Environment::ConstantEntry
            entry.decl
          when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
            entry.primary_decl
          when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
            entry.decl
          else
            raise
          end
        end

        def deprecated?
          if AnnotationsHelper.deprecated_type_name?(full_name, env)
            true
          else
            false
          end
        end
      end

      SimpleMethodNameItem = _ = Struct.new(:identifier, :range, :receiver_type, :method_types, :method_member, :method_name, :deprecated, keyword_init: true) do
        # @implements SimpleMethodNameItem

        def comment
          case method_member
          when ::RBS::AST::Members::Base
            method_member.comment
          when ::RBS::AST::Ruby::Members::Base
            nil
          end
        end
      end

      ComplexMethodNameItem = _ = Struct.new(:identifier, :range, :receiver_type, :method_types, :method_decls, keyword_init: true) do
        # @implements ComplexMethodNameItem

        def method_names
          method_definitions.keys
        end

        def method_definitions
          method_decls.each.with_object({}) do |decl, hash| #$ Hash[method_name, RBS::Definition::Method::method_member]
            method_name = defining_method_name(
              decl.method_def.defined_in,
              decl.method_name.method_name,
              decl.method_def.member
            )
            hash[method_name] = decl.method_def.member
          end
        end

        def defining_method_name(type_name, name, member)
          case member
          when ::RBS::AST::Members::MethodDefinition
            if member.instance?
              InstanceMethodName.new(type_name: type_name, method_name: name)
            else
              SingletonMethodName.new(type_name: type_name, method_name: name)
            end
          when ::RBS::AST::Members::Attribute
            if member.kind == :instance
              InstanceMethodName.new(type_name: type_name, method_name: name)
            else
              SingletonMethodName.new(type_name: type_name, method_name: name)
            end
          when ::RBS::AST::Ruby::Members::DefMember, ::RBS::AST::Ruby::Members::AttributeMember
            InstanceMethodName.new(type_name: type_name, method_name: name)
          end
        end
      end

      GeneratedMethodNameItem = _ = Struct.new(:identifier, :range, :receiver_type, :method_types, keyword_init: true) do
        # @implements GeneratedMethodNameItem
      end

      class TypeNameItem < Struct.new(:env, :absolute_type_name, :relative_type_name, :range, keyword_init: true)
        def decl
          case
          when absolute_type_name.interface?
            env.interface_decls.fetch(absolute_type_name).decl
          when absolute_type_name.alias?
            env.type_alias_decls.fetch(absolute_type_name).decl
          when absolute_type_name.class?
            case entry = env.module_class_entry(absolute_type_name)
            when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
              entry.primary_decl
            when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
              entry.decl
            else
              raise "absolute_type_name=#{absolute_type_name}, relative_type_name=#{relative_type_name}"
            end
          else
            raise
          end
        end

        def comments
          comments = [] #: Array[RBS::AST::Comment]

          case
          when absolute_type_name.interface?
            if comment = env.interface_decls.fetch(absolute_type_name).decl.comment
              comments << comment
            end
          when absolute_type_name.alias?
            if comment = env.type_alias_decls.fetch(absolute_type_name).decl.comment
              comments << comment
            end
          when absolute_type_name.class?
            case entry = env.module_class_entry(absolute_type_name)
            when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
              entry.each_decl do |decl|
                case decl
                when ::RBS::AST::Declarations::Base
                  if comment = decl.comment
                    comments << comment
                  end
                when ::RBS::AST::Ruby::Declarations::Base
                  # noop
                end
              end
            when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
              if comment = entry.decl.comment
                comments << comment
              end
            else
              raise
            end
          else
            raise
          end

          comments
        end
      end

      class TextItem < Struct.new(:text, :help_text, :range, :label, keyword_init: true)
      end
    end
  end
end
