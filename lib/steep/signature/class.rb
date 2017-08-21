module Steep
  module Signature
    module Members
      class InstanceMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(InstanceMethod) && other.name == name && other.types == types
        end
      end

      class ModuleMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(ModuleMethod) && other.name == name && other.types == types
        end
      end

      class ModuleInstanceMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(ModuleInstanceMethod) && other.name == name && other.types == types
        end
      end

      class Include
        attr_reader :name

        def initialize(name:)
          @name = name
        end

        def ==(other)
          other.is_a?(Include) && other.name == name
        end
      end

      class Extend
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
      def instance_methods(assignability:, klass:, instance:, params:)
        methods = super

        hash = type_application_hash(params)

        members.each do |member|
          case member
          when Members::Include
            module_signature = assignability.lookup_included_signature(member.name)
            merge_methods(methods, module_signature.instance_methods(assignability: assignability,
                                                                     klass: klass,
                                                                     instance: instance,
                                                                     params: module_signature.type_application_hash(member.name.params)))
          end
        end

        members.each do |member|
          case member
          when Members::InstanceMethod, Members::ModuleInstanceMethod
            method_types = member.types.map {|type| type.substitute(klass: klass, instance: instance, params: hash) }
            merge_methods(methods, member.name => Steep::Interface::Method.new(types: method_types, super_method: nil))
          end
        end

        methods
      end

      def module_methods(assignability:, klass:, instance:, params:)
        methods = super

        members.each do |member|
          case member
          when Members::Include
            module_signature = assignability.lookup_included_signature(member.name)
            merge_methods(methods, module_signature.module_methods(assignability: assignability,
                                                                   klass: klass,
                                                                   instance: instance,
                                                                   params: module_signature.type_application_hash(member.name.params)))
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
            method_types = member.types.map {|type| type.substitute(klass: klass, instance: instance, params: {}) }
            merge_methods(methods, member.name => Steep::Interface::Method.new(types: method_types, super_method: nil))
          end
        end

        if self.is_a?(Class)
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

      def type_application_hash(args)
        Hash[params.zip(args)]
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
      def each_type
        if block_given?
          members.each do |member|
            case member
            when Members::InstanceMethod, Members::ModuleMethod, Members::ModuleInstanceMethod
              member.types.each do |method_type|
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
              yield member.name
            else
              raise "Unknown member: #{member.class.inspect}"
            end
          end
        else
          enum_for :each_type
        end
      end
    end

    class Module
      attr_reader :name
      attr_reader :params
      attr_reader :members
      attr_reader :self_type

      prepend WithMethods
      include WithMembers

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

      def module_methods(assignability:, klass:, instance:, params:)
        {}
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

      end
    end

    class Class
      attr_reader :name
      attr_reader :params
      attr_reader :members
      attr_reader :super_class

      prepend WithMethods
      include WithMembers

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

      def module_methods(assignability:, klass:, instance:, params:)
        class_methods = assignability.lookup_class_signature(Types::Name.instance(name: :Class)).instance_methods(assignability: assignability,
                                                                                                                  klass: klass,
                                                                                                                  instance: instance,
                                                                                                                  params: [])
        if self.name == :BasicObject
          class_methods
        else
          super_class = self.super_class || Types::Name.instance(name: :Object)
          signature = assignability.lookup_super_class_signature(super_class)

          hash = type_application_hash(params)
          super_class_params = super_class.params.map do |type|
            type.substitute(klass: klass, instance: instance, params: hash)
          end

          class_methods.merge!(signature.module_methods(assignability: assignability, klass: klass, instance: instance, params: super_class_params))
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
      end
    end
  end
end
