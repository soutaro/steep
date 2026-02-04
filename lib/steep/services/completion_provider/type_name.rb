module Steep
  module Services
    module CompletionProvider
      class TypeName
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
              namespace = $1 or raise
              NamespacePrefix.new(::RBS::Namespace.parse(namespace.reverse), namespace.size)
            when /\A::/
              NamespacePrefix.new(::RBS::Namespace.root, 2)
            when /\A(\w*[A-Za-z_])((::\w+[A-Z])+(::)?)/
              namespace = $1 or raise
              identifier = $2 or raise
              NamespacedIdentPrefix.new(::RBS::Namespace.parse(identifier.reverse), namespace.reverse, namespace.size + identifier.size)
            when /\A(\w*[A-Za-z_])::/
              namespace = $1 or raise
              NamespacedIdentPrefix.new(::RBS::Namespace.root, namespace.reverse, namespace.size + 2)
            when /\A(\w*[A-Za-z_])/
              identifier = $1 or raise
              RawIdentPrefix.new(identifier.reverse)
            end
          end
        end

        attr_reader :env, :context, :type_name_resolver, :map

        def initialize(env:, context:, dirs:)
          @env = env
          @context = context

          table = ::RBS::Environment::UseMap::Table.new()
          table.known_types.merge(env.class_decls.keys)
          table.known_types.merge(env.class_alias_decls.keys)
          table.known_types.merge(env.type_alias_decls.keys)
          table.known_types.merge(env.interface_decls.keys)
          table.compute_children

          @map = ::RBS::Environment::UseMap.new(table: table)
          dirs.each do |dir|
            case dir
            when ::RBS::AST::Directives::Use
              dir.clauses.each do |clause|
                @map.build_map(clause)
              end
            end
          end

          @type_name_resolver = ::RBS::Resolver::TypeNameResolver.build(env)
        end

        def each_outer_module(context = self.context, &block)
          if block
            if (parent, con = context)
              namespace = each_outer_module(parent, &block)
              case con
              when false
                namespace
              when ::RBS::TypeName
                ns = con.with_prefix(namespace).to_namespace
                yield(ns)
                ns
              end
            else
              yield(::RBS::Namespace.root)
              ::RBS::Namespace.root
            end
          else
            enum_for :each_outer_module
          end
        end

        def each_type_name(&block)
          if block
            env = self.env

            table = {} #: Hash[::RBS::Namespace, Array[::RBS::TypeName]]
            env.class_decls.each_key do |type_name|
              yield(type_name)
              (table[type_name.namespace] ||= []) << type_name
            end
            env.type_alias_decls.each_key do |type_name|
              yield(type_name)
              (table[type_name.namespace] ||= []) << type_name
            end
            env.interface_decls.each_key do |type_name|
              yield(type_name)
              (table[type_name.namespace] ||= []) << type_name
            end
            env.class_alias_decls.each_key do |type_name|
              yield(type_name)
              (table[type_name.namespace] ||= []) << type_name
            end

            env.class_alias_decls.each_key do |alias_name|
              normalized_name = env.normalize_module_name?(alias_name) or next
              each_type_name_under(alias_name, normalized_name, table: table, &block)
            end

            resolve_pairs = [] #: Array[[::RBS::TypeName, ::RBS::TypeName]]

            map.instance_eval do
              @map.each_key do |name|
                relative_name = ::RBS::TypeName.new(name: name, namespace: ::RBS::Namespace.empty)
                if absolute_name = resolve?(relative_name)
                  if env.type_name?(absolute_name)
                    # Yields only if the relative type name resolves to existing absolute type name
                    resolve_pairs << [relative_name, absolute_name]
                  end
                end
              end
            end

            resolve_pairs.each do |use_name, absolute_name|
              yield use_name
              each_type_name_under(use_name, absolute_name, table: table, &block)
            end
          else
            enum_for :each_type_name
          end
        end

        def each_type_name_under(module_name, normalized_name, table:, &block)
          if children = table.fetch(normalized_name.to_namespace, nil)
            module_namespace = module_name.to_namespace

            children.each do |normalized_child_name|
              child_name = ::RBS::TypeName.new(namespace: module_namespace, name: normalized_child_name.name)

              yield child_name

              if normalized_child_name.class?
                each_type_name_under(child_name, env.normalize_module_name(normalized_child_name), table: table, &block)
              end
            end
          end
        end

        def resolve_used_name(name)
          return nil if name.absolute?

          case
          when resolved = map.resolve?(name)
            resolved
          when name.namespace.empty?
            nil
          else
            if resolved_parent = resolve_used_name(name.namespace.to_type_name)
              resolved_name = ::RBS::TypeName.new(namespace: resolved_parent.to_namespace, name: name.name)
              if env.normalize_type_name?(resolved_name)
                resolved_name
              end
            end
          end
        end

        def resolve_name_in_context(name)
          if resolved_name = resolve_used_name(name)
            return [resolved_name, name]
          end

          name.absolute? or raise

          if normalized_name = env.normalize_type_name?(name)
            name.namespace.path.reverse_each.inject(::RBS::TypeName.new(namespace: ::RBS::Namespace.empty, name: name.name)) do |relative_name, component|
              if type_name_resolver.resolve(relative_name, context: context) == name
                return [normalized_name, relative_name]
              end

              ::RBS::TypeName.new(
                namespace: ::RBS::Namespace.new(path: [component, *relative_name.namespace.path], absolute: false),
                name: name.name
              )
            end

            if type_name_resolver.resolve(name.relative!, context: context) == name && !resolve_used_name(name.relative!)
              [normalized_name, name.relative!]
            else
              [normalized_name, name]
            end
          end
        end

        def find_type_names(prefix)
          case prefix
          when Prefix::RawIdentPrefix
            each_type_name.filter do |type_name|
              type_name.split.any? {|sym| sym.to_s.downcase.include?(prefix.ident.downcase) }
            end
          when Prefix::NamespacedIdentPrefix
            absolute_namespace =
              if prefix.namespace.empty?
                ::RBS::Namespace.root
              else
                type_name_resolver.resolve(prefix.namespace.to_type_name, context: context)&.to_namespace || prefix.namespace
              end

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
end
