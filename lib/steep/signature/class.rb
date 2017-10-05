module Steep
  module Signature
    module Members
      class InstanceMethod
        # @implements Steep__SignatureMember__Method

        # @dynamic name
        attr_reader :name
        # @dynamic types
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(self.class) && other.name == name && other.types == types
        end
      end

      class ModuleMethod
        # @implements Steep__SignatureMember__Method

        # @dynamic name
        attr_reader :name
        # @dynamic types
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(self.class) && other.name == name && other.types == types
        end
      end

      class ModuleInstanceMethod
        # @implements Steep__SignatureMember__Method

        # @dynamic name
        attr_reader :name
        # @dynamic types
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(self.class) && other.name == name && other.types == types
        end
      end

      class Include
        # @implements Steep__SignatureMember__Include

        # @dynamic name
        attr_reader :name

        def initialize(name:)
          @name = name
        end

        def ==(other)
          other.is_a?(Include) && other.name == name
        end
      end

      class Extend
        # @implements Steep__SignatureMember__Extend

        # @dynamic name
        attr_reader :name

        def initialize(name:)
          @name = name
        end

        def ==(other)
          other.is_a?(Extend) && other.name == name
        end
      end
    end

    module WithMethods
      # @implements Steep__Signature__WithMethods

      def instance_methods(assignability:, klass:, instance:, params:)
        methods = super

        hash = type_application_hash(params)

        members.each do |member|
          case member
          when Members::Include
            # @type var include_member: Steep__SignatureMember__Include
            include_member = member
            module_signature = assignability.lookup_included_signature(include_member.name)
            merge_methods(methods, module_signature.instance_methods(assignability: assignability,
                                                                     klass: klass,
                                                                     instance: instance,
                                                                     params: module_signature.type_application_hash(include_member.name.params)))

          end
        end

        members.each do |member|
          case member
          when Members::InstanceMethod, Members::ModuleInstanceMethod
            # @type var method_member: Steep__SignatureMember__Method
            method_member = member
            method_types = method_member.types.map {|type| type.substitute(klass: klass, instance: instance, params: hash) }
            merge_methods(methods, method_member.name => Steep::Interface::Method.new(types: method_types, super_method: nil))
          end
        end

        extensions = assignability.lookup_extensions(name)
        extensions.each do |extension|
          extension_methods = extension.instance_methods(assignability: assignability, klass: klass, instance: instance, params: [])
          merge_methods(methods, extension_methods)
        end

        methods
      end

      def module_methods(assignability:, klass:, instance:, params:, constructor:)
        methods = super

        members.each do |member|
          case member
          when Members::Include
            module_signature = assignability.lookup_included_signature(member.name)
            merge_methods(methods, module_signature.module_methods(assignability: assignability,
                                                                   klass: klass,
                                                                   instance: instance,
                                                                   params: module_signature.type_application_hash(member.name.params),
                                                                   constructor: constructor))
          when Members::Extend
            module_signature = assignability.lookup_included_signature(member.name)
            merge_methods(methods, module_signature.instance_methods(assignability: assignability,
                                                                     klass: klass,
                                                                     instance: instance,
                                                                     params: module_signature.type_application_hash(member.name.params)))
          end
        end

        members.each do |member|
          case member
          when Members::ModuleInstanceMethod, Members::ModuleMethod
            # @type var method_member: Steep__SignatureMember__Method
            method_member = member
            method_types = method_member.types.map {|type| type.substitute(klass: klass, instance: instance, params: {}) }
            merge_methods(methods, method_member.name => Steep::Interface::Method.new(types: method_types, super_method: nil))
          end
        end

        if is_class? && constructor
          instance_methods = instance_methods(assignability: assignability, klass: klass, instance: instance, params: params)
          new_method = if instance_methods[:initialize]
                         types = instance_methods[:initialize].types.map do |method_type|
                           method_type.updated(return_type: instance)
                         end
                         Steep::Interface::Method.new(types: types, super_method: nil)
                       else
                         Steep::Interface::Method.new(types: [Steep::Interface::MethodType.new(type_params: [],
                                                                                               params: Steep::Interface::Params.empty,
                                                                                               block: nil,
                                                                                               return_type: instance)],
                                                      super_method: nil)
                       end
          methods[:new] = new_method
        end

        methods
      end

      def merge_methods(methods, hash)
        hash.each_key do |name|
          method = hash[name]

          methods[name] = Steep::Interface::Method.new(types: method.types,
                                                       super_method: methods[name])
        end
      end
    end

    module WithMembers
      # @implements Steep__Signature__WithMembers
      def each_type
        if block_given?
          members.each do |member|
            case member
            when Members::InstanceMethod, Members::ModuleMethod, Members::ModuleInstanceMethod
              # @type var method_member: Steep__SignatureMember__Method
              method_member = member
              method_member.types.each do |method_type|
                method_type.params.each_type do |type|
                  yield type
                end
                yield method_type.return_type
                if method_type.block
                  method_type.block.params.each_type do |type|
                    yield type
                  end
                  yield method_type.block.return_type
                end
              end
            when Members::Include, Members::Extend
              # @type var mixin_member: _Steep__SignatureMember__Mixin
              mixin_member = member
              yield mixin_member.name
            else
              raise "Unknown member: #{member.class.inspect}"
            end
          end
        else
          enum_for :each_type
        end
      end

      def validate_mixins(assignability, interface)
        members.each do |member|
          if member.is_a?(Members::Include)
            module_signature = assignability.lookup_included_signature(member.name)

            if module_signature.self_type
              self_type = module_signature.self_type.substitute(klass: Types::Name.module(name: name),
                                                                instance: Types::Name.instance(name: name),
                                                                params: {})
              self_interface = assignability.resolve_interface(self_type.name, member.name.params)

              unless assignability.test_interface(interface, self_interface, [])
                assignability.errors << Errors::InvalidSelfType.new(signature: self, member: member)
              end
            end
          end
        end
      end
    end

    module WithParams
      # @implements Steep__Signature__WithParams

      def type_application_hash(args)
        Hash[params.zip(args)]
      end
    end

    class Module
      # @implements Steep__Signature__Module

      # @dynamic name
      attr_reader :name
      # @dynamic params
      attr_reader :params
      # @dynamic members
      attr_reader :members
      # @dynamic self_type
      attr_reader :self_type

      prepend WithMethods
      include WithMembers
      include WithParams

      def initialize(name:, params:, members:, self_type:)
        @name = name
        @members = members
        @params = params
        @self_type = self_type
      end

      def ==(other)
        other.is_a?(Module) && other.name == name && other.params == params && other.members == members && other.self_type == self_type
      end

      def instance_methods(assignability:, klass:, instance:, params:)
        {}
      end

      def module_methods(assignability:, klass:, instance:, params:, constructor:)
        {}
      end

      def each_type
        if block_given?
          yield self_type if self_type
          super do |type|
            yield type
          end
        else
          enum_for :each_type
        end
      end

      def validate(assignability)
        each_type do |type|
          assignability.validate_type_presence self, type
        end

        interface = assignability.resolve_interface(TypeName::Instance.new(name: name),
                                                    params.map {|x| Types::Var.new(name: x) })

        validate_mixins(assignability, interface)
      end

      def is_class?
        false
      end
    end

    class Class
      # @implements Steep__Signature__Class

      # @dynamic name
      attr_reader :name
      # @dynamic params
      attr_reader :params
      # @dynamic members
      attr_reader :members
      # @dynamic super_class
      attr_reader :super_class

      prepend WithMethods
      include WithMembers
      include WithParams

      def initialize(name:, params:, members:, super_class:)
        @name = name
        @members = members
        @params = params
        @super_class = super_class
      end

      def ==(other)
        other.is_a?(Class) && other.name == name && other.params == params && other.members == members && other.super_class == super_class
      end

      def instance_methods(assignability:, klass:, instance:, params:)
        if self.name == :BasicObject
          {}
        else
          super_class = self.super_class || Types::Name.instance(name: :Object)
          signature = assignability.lookup_super_class_signature(super_class)

          hash = type_application_hash(params)
          super_class_params = super_class.params.map do |type|
            type.substitute(klass: klass, instance: instance, params: hash)
          end

          signature.instance_methods(assignability: assignability, klass: klass, instance: instance, params: super_class_params)
        end
      end

      def module_methods(assignability:, klass:, instance:, params:, constructor:)
        signature = assignability.lookup_class_signature(Types::Name.instance(name: :Class))
        class_methods = signature.instance_methods(assignability: assignability,
                                                   klass: klass,
                                                   instance: instance,
                                                   params: [instance])
        if self.name == :BasicObject
          class_methods
        else
          super_class = self.super_class || Types::Name.instance(name: :Object)
          signature = assignability.lookup_super_class_signature(super_class)

          hash = type_application_hash(params)
          super_class_params = super_class.params.map do |type|
            type.substitute(klass: klass, instance: instance, params: hash)
          end

          class_methods.merge!(signature.module_methods(assignability: assignability,
                                                        klass: klass,
                                                        instance: instance,
                                                        params: super_class_params,
                                                        constructor: constructor))
        end
      end

      def each_type
        if block_given?
          yield super_class if super_class
          super do |type|
            yield type
          end
        else
          enum_for :each_type
        end
      end

      def validate(assignability)
        each_type do |type|
          assignability.validate_type_presence self, type
        end

        interface = assignability.resolve_interface(TypeName::Instance.new(name: name),
                                                    params.map {|x| Types::Var.new(name: x) })

        interface.methods.each_key do |method_name|
          method = interface.methods[method_name]
          if method.super_method
            assignability.validate_method_compatibility(self, method_name, method)
          end
        end

        validate_mixins(assignability, interface)
      end

      def is_class?
        true
      end
    end
  end
end
