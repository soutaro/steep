module Steep
  module Index
    class RBSIndex
      class TypeEntry
        attr_reader :type_name
        attr_reader :declarations
        attr_reader :references

        def initialize(type_name:)
          @type_name = type_name
          @declarations = Set[]
          @references = Set[]
        end

        def add_declaration(decl)
          case decl
          when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
            declarations << decl
          when RBS::AST::Declarations::Interface
            declarations << decl
          when RBS::AST::Declarations::TypeAlias
            declarations << decl
          when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
            declarations << decl
          else
            raise "Unexpected type declaration: #{decl}"
          end

          self
        end

        def add_reference(ref)
          case ref
          when RBS::AST::Members::MethodDefinition
            references << ref
          when RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
            references << ref
          when RBS::AST::Members::InstanceVariable, RBS::AST::Members::ClassInstanceVariable, RBS::AST::Members::ClassVariable
            references << ref
          when RBS::AST::Members::Include, RBS::AST::Members::Extend
            references << ref
          when RBS::AST::Declarations::Module, RBS::AST::Declarations::Class
            references << ref
          when RBS::AST::Declarations::Constant, RBS::AST::Declarations::Global
            references << ref
          when RBS::AST::Declarations::TypeAlias
            references << ref
          when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
            references << ref
          else
            raise "Unexpected type reference: #{ref}"
          end

          self
        end
      end

      class MethodEntry
        attr_reader :method_name
        attr_reader :declarations
        attr_reader :references

        def initialize(method_name:)
          @method_name = method_name
          @declarations = Set[]
          @references = Set[]
        end

        def add_declaration(decl)
          case decl
          when RBS::AST::Members::MethodDefinition,
            RBS::AST::Members::Alias,
            RBS::AST::Members::AttrWriter,
            RBS::AST::Members::AttrReader,
            RBS::AST::Members::AttrAccessor
            declarations << decl
          else
            raise "Unexpected method declaration: #{decl}"
          end

          self
        end
      end

      class ConstantEntry
        attr_reader :const_name
        attr_reader :declarations

        def initialize(const_name:)
          @const_name = const_name
          @declarations = Set[]
        end

        def add_declaration(decl)
          case decl
          when RBS::AST::Declarations::Constant
            declarations << decl
          else
            raise
          end

          self
        end
      end

      class GlobalEntry
        attr_reader :global_name
        attr_reader :declarations

        def initialize(global_name:)
          @global_name = global_name
          @declarations = Set[]
        end

        def add_declaration(decl)
          case decl
          when RBS::AST::Declarations::Global
            declarations << decl
          else
            raise
          end

          self
        end
      end

      attr_reader :type_index
      attr_reader :method_index
      attr_reader :const_index
      attr_reader :global_index

      def initialize()
        @type_index = {}
        @method_index = {}
        @const_index = {}
        @global_index = {}
      end

      def entry(type_name: nil, method_name: nil, const_name: nil, global_name: nil)
        case
        when type_name
          type_index[type_name] ||= TypeEntry.new(type_name: type_name)
        when method_name
          method_index[method_name] ||= MethodEntry.new(method_name: method_name)
        when const_name
          const_index[const_name] ||= ConstantEntry.new(const_name: const_name)
        when global_name
          global_index[global_name] ||= GlobalEntry.new(global_name: global_name)
        else
          raise
        end
      end

      def each_entry(&block)
        if block
          type_index.each_value(&block)
          method_index.each_value(&block)
          const_index.each_value(&block)
          global_index.each_value(&block)
        else
          enum_for(:each_entry)
        end
      end

      def add_type_declaration(type_name, declaration)
        entry(type_name: type_name).add_declaration(declaration)
      end

      def add_method_declaration(method_name, member)
        entry(method_name: method_name).add_declaration(member)
      end

      def add_constant_declaration(const_name, decl)
        entry(const_name: const_name).add_declaration(decl)
      end

      def add_global_declaration(global_name, decl)
        entry(global_name: global_name).add_declaration(decl)
      end

      def each_declaration(type_name: nil, method_name: nil, const_name: nil, global_name: nil, &block)
        if block
          entry = __skip__ = entry(type_name: type_name, method_name: method_name, const_name: const_name, global_name: global_name)
          entry.declarations.each(&block)
        else
          enum_for(:each_declaration, type_name: type_name, method_name: method_name, const_name: const_name, global_name: global_name)
        end
      end

      def add_type_reference(type_name, ref)
        entry(type_name: type_name).add_reference(ref)
      end

      def each_reference(type_name:, &block)
        if block
          case
          when type_name
            entry(type_name: type_name).references.each(&block)
          end
        else
          enum_for(:each_reference, type_name: type_name)
        end
      end

      class Builder
        attr_reader :index

        def initialize(index:)
          @index = index
        end

        def member(type_name, member)
          case member
          when RBS::AST::Members::MethodDefinition
            member.overloads.each do |overload|
              overload.method_type.each_type do |type|
                type_reference type, from: member
              end
            end

            if member.instance?
              method_name = InstanceMethodName.new(type_name: type_name, method_name: member.name)
              index.add_method_declaration(method_name, member)
            end

            if member.singleton?
              method_name = SingletonMethodName.new(type_name: type_name, method_name: member.name)
              index.add_method_declaration(method_name, member)
            end

          when RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
            type_reference member.type, from: member

            if member.is_a?(RBS::AST::Members::AttrReader) || member.is_a?(RBS::AST::Members::AttrAccessor)
              method_name = case member.kind
                            when :instance
                              InstanceMethodName.new(type_name: type_name, method_name: member.name)
                            when :singleton
                              SingletonMethodName.new(type_name: type_name, method_name: member.name)
                            else
                              raise
                            end
              index.add_method_declaration(method_name, member)
            end

            if member.is_a?(RBS::AST::Members::AttrWriter) || member.is_a?(RBS::AST::Members::AttrAccessor)
              method_name = case member.kind
                            when :instance
                              InstanceMethodName.new(type_name: type_name, method_name: "#{member.name}=".to_sym)
                            when :singleton
                              SingletonMethodName.new(type_name: type_name, method_name: "#{member.name}=".to_sym)
                            else
                              raise
                            end
              index.add_method_declaration(method_name, member)
            end

          when RBS::AST::Members::InstanceVariable, RBS::AST::Members::ClassVariable, RBS::AST::Members::ClassInstanceVariable
            type_reference member.type, from: member

          when RBS::AST::Members::Include, RBS::AST::Members::Extend
            index.add_type_reference member.name, member
            member.args.each do |type|
              type_reference type, from: member
            end

          when RBS::AST::Members::Alias
            if member.instance?
              new_name = InstanceMethodName.new(type_name: type_name, method_name: member.new_name)
              index.add_method_declaration(new_name, member)
            end

            if member.singleton?
              new_name = SingletonMethodName.new(type_name: type_name, method_name: member.new_name)
              index.add_method_declaration(new_name, member)
            end
          end
        end

        def type_reference(type, from:)
          case type
          when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Alias, RBS::Types::Interface
            index.add_type_reference(type.name, from)
          end

          type.each_type do |ty|
            type_reference ty, from: from
          end
        end

        def env(env)
          env.class_decls.each do |name, decl|
            decl.decls.each do |d|
              index.add_type_declaration(name, d.decl)

              case d.decl
              when RBS::AST::Declarations::Class
                if super_class = d.decl.super_class
                  index.add_type_reference(super_class.name, d.decl)
                  super_class.args.each do |type|
                    type_reference(type, from: d.decl)
                  end
                end
              when RBS::AST::Declarations::Module
                d.decl.self_types.each do |self_type|
                  index.add_type_reference(self_type.name, d.decl)
                  self_type.args.each do |type|
                    type_reference(type, from: d.decl)
                  end
                end
              end

              d.decl.members.each do |member|
                member(name, member)
              end
            end
          end

          env.class_alias_decls.each do |name, entry|
            index.add_type_declaration(name, entry.decl)
            index.add_type_reference(entry.decl.old_name, entry.decl)
          end

          env.interface_decls.each do |name, decl|
            index.add_type_declaration(name, decl.decl)

            decl.decl.members.each do |member|
              member(name, member)
            end
          end

          env.type_alias_decls.each do |name, decl|
            index.add_type_declaration(name, decl.decl)
            type_reference decl.decl.type, from: decl.decl
          end

          env.constant_decls.each do |name, decl|
            index.add_constant_declaration(name, decl.decl)
            type_reference decl.decl.type, from: decl.decl
          end

          env.global_decls.each do |name, decl|
            index.add_global_declaration(name, decl.decl)
            type_reference decl.decl.type, from: decl.decl
          end
        end
      end
    end
  end
end
