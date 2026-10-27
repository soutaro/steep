module Steep
  module SetTheoretic
    # Reverse indexes of the class hierarchy declared in an RBS environment: which classes inherit from a class, and
    # which classes and modules mix a module in.
    #
    # The emptiness check consults it to tell `empty_in_rbs` from `inhabited`: `Foo & Taggable` has no instance in the
    # environment when no class under `Foo` includes `Taggable`.
    class ClassIndex
      attr_reader :env

      attr_reader :ancestor_builder

      def initialize(env:, ancestor_builder:)
        @env = env
        @ancestor_builder = ancestor_builder
      end

      def class?(name)
        env.class_decl?(name)
      end

      def module?(name)
        env.module_decl?(name)
      end

      # The classes that inherit from the class, transitively, the class itself excluded
      def descendants(class_name)
        @descendants ||= {} #: Hash[RBS::TypeName, names]
        @descendants[class_name] ||= closure(class_name) {|name| direct_subclasses.fetch(name, EMPTY_SET) }
      end

      # The classes and modules that have the module as an instance ancestor, transitively: the ones that include or
      # prepend it, the ones that include those modules, and the subclasses of those classes
      def includers(module_name)
        @includers ||= {} #: Hash[RBS::TypeName, names]
        @includers[module_name] ||= closure(module_name) do |name|
          next_names = direct_includers.fetch(name, EMPTY_SET)
          if class?(name)
            next_names = next_names + direct_subclasses.fetch(name, EMPTY_SET)
          end
          next_names
        end
      end

      # The classes and modules that have the module as a singleton ancestor, transitively: the ones that extend it,
      # the ones that extend a module including it, and the subclasses of those classes
      def extenders(module_name)
        @extenders ||= {} #: Hash[RBS::TypeName, names]
        @extenders[module_name] ||= begin
          names = Set[] #: Set[RBS::TypeName]
          ([module_name] + includers(module_name).to_a).each do |mod|
            direct_extenders.fetch(mod, EMPTY_SET).each do |name|
              names << name
              names.merge(descendants(name)) if class?(name)
            end
          end
          names
        end
      end

      # The classes whose instances belong to the instance type of `name`: the class and its descendants, or the classes
      # mixing the module in
      def instance_classes(name)
        if class?(name)
          descendants(name) + [name]
        elsif module?(name)
          includers(name).select {|n| class?(n) }.to_set
        else
          Set[]
        end
      end

      # `true` if the environment declares a class whose instances belong to both instance types
      def common_instance?(name1, name2)
        instance_classes(name1).intersect?(instance_classes(name2))
      end

      # `true` if the environment declares a class, under `class_name` or `class_name` itself, whose singletons extend the module
      def singleton_extends?(class_name, module_name)
        extenders(module_name).include?(class_name) || extenders(module_name).intersect?(descendants(class_name))
      end

      def direct_subclasses
        build unless @direct_subclasses
        @direct_subclasses or raise
      end

      def direct_includers
        build unless @direct_includers
        @direct_includers or raise
      end

      def direct_extenders
        build unless @direct_extenders
        @direct_extenders or raise
      end

      private

      EMPTY_SET = Set[].freeze #: Set[RBS::TypeName]

      def closure(start)
        result = Set[] #: Set[RBS::TypeName]
        queue = yield(start).to_a
        until queue.empty?
          name = queue.shift or raise
          next if result.include?(name)
          result << name
          queue.concat(yield(name).to_a)
        end
        result
      end

      def build
        subclasses = {} #: Hash[RBS::TypeName, Set[RBS::TypeName]]
        includers = {} #: Hash[RBS::TypeName, Set[RBS::TypeName]]
        extenders = {} #: Hash[RBS::TypeName, Set[RBS::TypeName]]

        env.class_decls.each_key do |name|
          begin
            instance = ancestor_builder.one_instance_ancestors(name)
            singleton = ancestor_builder.one_singleton_ancestors(name)
          rescue RBS::BaseError
            # A broken declaration is reported by the signature validation; it only loses its edges here
            next
          end

          if (super_class = instance.super_class).is_a?(RBS::Definition::Ancestor::Instance)
            (subclasses[env.normalize_module_name(super_class.name)] ||= Set[]) << name
          end
          instance.each_included_module do |mod|
            (includers[env.normalize_module_name(mod.name)] ||= Set[]) << name
          end
          instance.each_prepended_module do |mod|
            (includers[env.normalize_module_name(mod.name)] ||= Set[]) << name
          end
          singleton.each_extended_module do |mod|
            (extenders[env.normalize_module_name(mod.name)] ||= Set[]) << name
          end
        end

        @direct_subclasses = subclasses
        @direct_includers = includers
        @direct_extenders = extenders
      end
    end
  end
end
