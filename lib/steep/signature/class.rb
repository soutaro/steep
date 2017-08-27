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
          when Members::InstanceMethod
            methods[member.name] = member.types.map {|type| type.substitute(klass: klass, instance: instance, params: hash) }
          when Members::ModuleInstanceMethod
            methods[member.name] = member.types.map {|type| type.substitute(klass: klass, instance: instance, params: hash) }
          when Members::Include
            module_signature = assignability.lookup_included_signature(member.name)
            methods.merge!(module_signature.instance_methods(assignability: assignability,
                                                             klass: klass,
                                                             instance: instance,
                                                             params: module_signature.type_application_hash(member.name.params)))
          end
        end

        methods
      end

      def module_methods(assignability:, klass:, instance:, params:)
        methods = super

        members.each do |member|
          case member
          when Members::ModuleInstanceMethod, Members::ModuleMethod
            methods[member.name] = member.types.map {|type| type.substitute(klass: klass, instance: instance, params: {}) }
          when Members::Include
            module_signature = assignability.lookup_included_signature(member.name)
            methods.merge!(module_signature.module_methods(assignability: assignability,
                                                           klass: klass,
                                                           instance: instance,
                                                           params: module_signature.type_application_hash(member.name.params)))
          when Members::Extend
            module_signature = assignability.lookup_included_signature(member.name)
            methods.merge!(module_signature.instance_methods(assignability: assignability,
                                                             klass: klass,
                                                             instance: instance,
                                                             params: module_signature.type_application_hash(member.name.params)))
          end
        end

        if self.is_a?(Class)
          instance_methods = instance_methods(assignability: assignability, klass: klass, instance: instance, params: params)
          methods[:new] = if instance_methods[:initialize]
                            instance_methods[:initialize].map {|type| type.updated(return_type: instance) }
                          else
                            [Steep::Interface::MethodType.new(type_params: [],
                                                              params: Steep::Interface::Params.empty,
                                                              block: nil,
                                                              return_type: instance)]
                          end
        end

        methods
      end

      def type_application_hash(args)
        Hash[params.zip(args)]
      end
    end

    class Module
      attr_reader :name
      attr_reader :params
      attr_reader :members
      attr_reader :self_type

      prepend WithMethods

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
    end

    class Class
      attr_reader :name
      attr_reader :params
      attr_reader :members
      attr_reader :super_class

      prepend WithMethods

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
    end
  end
end
