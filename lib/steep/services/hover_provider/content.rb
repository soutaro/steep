module Steep
  module Services
    module HoverProvider
      TypeContent = _ = Struct.new(:node, :type, :location, keyword_init: true)
      VariableContent = _ = Struct.new(:node, :name, :type, :location, keyword_init: true)
      TypeAssertionContent = _ = Struct.new(:node, :original_type, :asserted_type, :location, keyword_init: true)
      MethodCallContent = _ = Struct.new(:node, :method_call, :location, keyword_init: true)
      DefinitionContent = _ = Struct.new(:node, :method_name, :method_type, :definition, :location, keyword_init: true)
      ConstantContent = _ = Struct.new(:location, :full_name, :type, :decl, keyword_init: true) do
        # @implements ConstantContent

          def comments
            case
            when decl = class_decl
              decl.each_decl.map do |decl|
                case decl
                when ::RBS::AST::Declarations::Base
                  decl.comment
                when ::RBS::AST::Ruby::Declarations::Base
                  nil
                end

              end
            when decl = class_alias
              [decl.decl.comment]
            when decl = constant_decl
              [decl.decl.comment]
            else
              raise
            end.compact
          end

          def class_decl
            case decl
            when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
              decl
            end
          end

          def class_alias
            case decl
            when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
              decl
            end
          end

          def constant_decl
            if decl.is_a?(::RBS::Environment::ConstantEntry)
              decl
            end
          end

          def constant?
            constant_decl ? true : false
          end

          def class_or_module?
            (class_decl || class_alias) ?  true : false
        end
      end

      TypeAliasContent = _ = Struct.new(:location, :decl, keyword_init: true)
      ClassTypeContent = _ = Struct.new(:location, :decl, keyword_init: true)
      InterfaceTypeContent = _ = Struct.new(:location, :decl, keyword_init: true)
    end
  end
end