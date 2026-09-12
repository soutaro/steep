module Steep
  module Server
    class RBSEntryBuilder
      attr_reader :entries

      def initialize
        @entries = {}
        @seen = Set[]
        @paths = {}
      end

      def env(env)
        env.class_decls.each do |name, entry|
          entry.each_decl do |decl|
            class_decl(name, decl)
          end
        end

        env.class_alias_decls.each do |name, entry|
          decl = entry.decl
          case decl
          when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
            definition(name.to_s, child_location(decl.location, :new_name))
            reference(decl.old_name, child_location(decl.location, :old_name))
          when RBS::AST::Ruby::Declarations::ClassModuleAliasDecl
            definition(name.to_s, decl.name_location)
            if (annotation = decl.annotation) && (old_name = annotation.type_name)
              reference(old_name, annotation.type_name_location)
            end
          end
        end

        env.interface_decls.each do |name, entry|
          decl = entry.decl
          definition(name.to_s, child_location(decl.location, :name))
          type_params(decl.type_params)
          members(name, decl.members)
        end

        env.type_alias_decls.each do |name, entry|
          decl = entry.decl
          definition(name.to_s, child_location(decl.location, :name))
          type_params(decl.type_params)
          type(decl.type)
        end

        env.constant_decls.each do |name, entry|
          decl = entry.decl
          case decl
          when RBS::AST::Declarations::Constant
            definition(name.to_s, child_location(decl.location, :name))
            type(decl.type)
          when RBS::AST::Ruby::Declarations::ConstantDecl
            definition(name.to_s, decl.name_location)
            type(decl.type)
          end
        end

        env.global_decls.each do |name, entry|
          decl = entry.decl
          definition(name.to_s, child_location(decl.location, :name))
          type(decl.type)
        end

        self
      end

      private

      def class_decl(name, decl)
        case decl
        when RBS::AST::Declarations::Class
          definition(name.to_s, child_location(decl.location, :name))
          if super_class = decl.super_class
            reference(super_class.name, child_location(super_class.location, :name))
            super_class.args.each { |arg| type(arg) }
          end
          type_params(decl.type_params)
          members(name, decl.members)
        when RBS::AST::Declarations::Module
          definition(name.to_s, child_location(decl.location, :name))
          decl.self_types.each do |self_type|
            reference(self_type.name, child_location(self_type.location, :name))
            self_type.args.each { |arg| type(arg) }
          end
          type_params(decl.type_params)
          members(name, decl.members)
        when RBS::AST::Ruby::Declarations::ClassDecl
          definition(name.to_s, decl.name_location)
          if super_class = decl.super_class
            reference(super_class.type_name, super_class.type_name_location)
            super_class.type_args.each { |arg| type(arg) }
          end
          members(name, decl.members)
        when RBS::AST::Ruby::Declarations::ModuleDecl
          definition(name.to_s, decl.name_location)
          members(name, decl.members)
        end
      end

      def members(type_name, members)
        members.each do |member|
          case member
          when RBS::AST::Members::MethodDefinition
            location = child_location(member.location, :name)
            method_definition(type_name, member.name, :instance, location) if member.instance?
            method_definition(type_name, member.name, :singleton, location) if member.singleton?
            member.overloads.each do |overload|
              method_type(overload.method_type)
            end
          when RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter, RBS::AST::Members::AttrAccessor
            location = child_location(member.location, :name)
            unless member.is_a?(RBS::AST::Members::AttrWriter)
              method_definition(type_name, member.name, member.kind, location)
            end
            unless member.is_a?(RBS::AST::Members::AttrReader)
              method_definition(type_name, :"#{member.name}=", member.kind, location)
            end
            type(member.type)
          when RBS::AST::Members::Alias
            new_name = child_location(member.location, :new_name)
            old_name = child_location(member.location, :old_name)
            if member.instance?
              method_definition(type_name, member.new_name, :instance, new_name)
              method_reference(type_name, member.old_name, :instance, old_name)
            end
            if member.singleton?
              method_definition(type_name, member.new_name, :singleton, new_name)
              method_reference(type_name, member.old_name, :singleton, old_name)
            end
          when RBS::AST::Members::InstanceVariable, RBS::AST::Members::ClassVariable, RBS::AST::Members::ClassInstanceVariable
            type(member.type)
          when RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend
            reference(member.name, child_location(member.location, :name))
            member.args.each { |arg| type(arg) }
          when RBS::AST::Ruby::Members::DefMember
            method_definition(type_name, member.name, member.kind, member.name_location)
            member.overloads.each do |overload|
              method_type(overload.method_type)
            end
          when RBS::AST::Ruby::Members::MixinMember
            reference(member.module_name, member.name_location)
            member.type_args.each { |arg| type(arg) }
          when RBS::AST::Ruby::Members::AttributeMember
            if attr_type = member.type
              type(attr_type)
            end
          when RBS::AST::Ruby::Members::InstanceVariableMember
            type(member.type)
          when RBS::AST::Ruby::Members::ModuleSelfMember
            member.args.each { |arg| type(arg) }
          end
        end
      end

      def method_type(method_type)
        type_params(method_type.type_params)
        method_type.each_type { |type| type(type) }
      end

      def type_params(params)
        params.each do |param|
          if upper_bound = param.upper_bound_type
            type(upper_bound)
          end
          if lower_bound = param.lower_bound_type
            type(lower_bound)
          end
          if default = param.default_type
            type(default)
          end
        end
      end

      def type(type)
        case type
        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
          reference(type.name, child_location(type.location, :name))
        end

        type.each_type { |arg| type(arg) }
      end

      def definition(name, location)
        push(name, :definition, location)
      end

      def reference(type_name, location)
        push(type_name.to_s, :reference, location)
      end

      def method_definition(type_name, method_name, kind, location)
        push(method_name_string(type_name, method_name, kind), :definition, location)
      end

      def method_reference(type_name, method_name, kind, location)
        push(method_name_string(type_name, method_name, kind), :reference, location)
      end

      def method_name_string(type_name, method_name, kind)
        case kind
        when :instance
          InstanceMethodName.new(type_name: type_name, method_name: method_name).to_s
        when :singleton
          SingletonMethodName.new(type_name: type_name, method_name: method_name).to_s
        else
          raise "Unexpected method kind: #{kind}"
        end
      end

      def push(name, role, location)
        return unless location

        buffer_name = location.buffer.name.to_s
        path = (@paths[buffer_name] ||= Pathname(buffer_name))

        key = [name, role, path, location.start_line, location.start_column, location.end_line, location.end_column] #: Array[untyped]
        return unless @seen.add?(key)

        (entries[path] ||= []) << TypeCheckDatabase::Entry.new(
          name: name,
          role: role,
          start_line: location.start_line - 1,
          start_character: location.start_column,
          end_line: location.end_line - 1,
          end_character: location.end_column
        )
      end

      def child_location(location, key)
        if location && location.key?(key)
          location[key]
        end
      end
    end
  end
end
