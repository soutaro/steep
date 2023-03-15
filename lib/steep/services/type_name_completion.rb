module Steep
  module Services
    class TypeNameCompletion
      module Prefix
        RawIdentPrefix = _ = Struct.new(:ident) do
          # @implements RawIdentPrefix

          def const_name?
            ident.start_with?(/[A-Z]/)
          end

          def size
            ident.length
          end
        end

        NamespacedIdentPrefix = _ = Struct.new(:namespace, :ident, :size) do
          # @implements NamespacedIdentPrefix

          def const_name?
            ident.start_with?(/[A-Z]/)
          end
        end

        NamespacePrefix = _ = Struct.new(:namespace, :size)

        def self.parse(buffer, line:, column:)
          pos = buffer.loc_to_pos([line, column])
          prefix = buffer.content[0...pos] or raise
          prefix.reverse!

          case prefix
          when /\A((::\w+[A-Z])+(::)?)/
            NamespacePrefix.new(RBS::Namespace.parse($1.reverse), $1.size)
          when /\A::/
            NamespacePrefix.new(RBS::Namespace.root, 2)
          when /\A(\w*[A-Za-z_])((::\w+[A-Z])+(::)?)/
            NamespacedIdentPrefix.new(RBS::Namespace.parse($2.reverse), $1.reverse, $1.size + $2.size)
          when /\A(\w*[A-Za-z_])::/
            NamespacedIdentPrefix.new(RBS::Namespace.root, $1.reverse, $1.size + 2)
          when /\A(\w*[A-Za-z_])/
            RawIdentPrefix.new($1.reverse)
          end
        end
      end

      attr_reader :env, :context, :type_name_resolver, :map

      def initialize(env:, context:, dirs:)
        @env = env
        @context = context

        table = RBS::Environment::UseMap::Table.new()
        table.known_types.merge(env.class_decls.keys)
        table.known_types.merge(env.class_alias_decls.keys)
        table.known_types.merge(env.type_alias_decls.keys)
        table.known_types.merge(env.interface_decls.keys)
        table.compute_children

        @map = RBS::Environment::UseMap.new(table: table)
        dirs.each do |dir|
          dir.clauses.each do |clause|
            @map.build_map(clause)
          end
        end

        @type_name_resolver = RBS::Resolver::TypeNameResolver.new(env)
      end

      def each_outer_module(context = self.context, &block)
        if block
          if (parent, con = context)
            namespace = each_outer_module(parent, &block)
            case con
            when false
              namespace
            when RBS::TypeName
              ns = con.with_prefix(namespace).to_namespace
              yield(ns)
              ns
            end
          else
            yield(RBS::Namespace.root)
            RBS::Namespace.root
          end
        else
          enum_for :each_outer_module
        end
      end

      def each_type_name(&block)
        if block
          map.instance_eval do
            @map.each_key do |name|
              yield RBS::TypeName.new(name: name, namespace: RBS::Namespace.empty)
            end
          end
          env.class_decls.each_key(&block)
          env.class_alias_decls.each_key(&block)
          env.type_alias_decls.each_key(&block)
          env.interface_decls.each_key(&block)
        else
          enum_for :each_type_name
        end
      end

      def resolve_name_in_context(name)
        if resolved_name = map.resolve?(name)
          return [resolved_name, name]
        end

        name.absolute? or raise

        name.namespace.path.reverse_each.inject(RBS::TypeName.new(namespace: RBS::Namespace.empty, name: name.name)) do |relative_name, component|
          if type_name_resolver.resolve(relative_name, context: context) == name
            return [name, relative_name]
          end

          RBS::TypeName.new(
            namespace: RBS::Namespace.new(path: [component, *relative_name.namespace.path], absolute: false),
            name: name.name
          )
        end

        if type_name_resolver.resolve(name.relative!, context: context) == name && !map.resolve?(name.relative!)
          [name, name.relative!]
        else
          [name, name]
        end
      end

      def find_type_names(prefix)
        case prefix
        when Prefix::RawIdentPrefix
          each_type_name.filter do |type_name|
            type_name.split.any? {|sym| sym.to_s.downcase.include?(prefix.ident.downcase) }
          end
        when Prefix::NamespacedIdentPrefix
          absolute_namespace = type_name_resolver.resolve(prefix.namespace.to_type_name, context: context)&.to_namespace || prefix.namespace

          each_type_name.filter do|name|
            name.namespace == absolute_namespace &&
              name.name.to_s.downcase.include?(prefix.ident.downcase)
          end
        when Prefix::NamespacePrefix
          absolute_namespace = type_name_resolver.resolve(prefix.namespace.to_type_name, context: context)&.to_namespace || prefix.namespace
          each_type_name.filter {|name| name.namespace == absolute_namespace }
        else
          # Returns all of the accessible type names from the context
          namespaces = each_outer_module.to_set
          # Relative type name means a *use*d type name
          each_type_name.filter {|name| namespaces.include?(name.namespace) || !name.absolute? }
        end
      end
    end
  end
end
