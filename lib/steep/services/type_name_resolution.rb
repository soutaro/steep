module Steep
  module Services
    class TypeNameResolution
      class Resolver < RBS::Resolver::TypeNameResolver
        attr_reader :probes

        def initialize(all_names, aliases)
          super
          @probes = {}
          @entries = {}
          @current = nil
        end

        def record(path)
          names = [] #: Array[RBS::TypeName]
          @current = names
          yield
          probes[path] = Set.new(names)
        ensure
          @current = nil
        end

        private

        def has_type_name?(full_name)
          @current&.push(full_name)
          super
        end

        def aliased_name?(type_name)
          @current&.push(type_name)
          super
        end

        def try_cache(type_name, context)
          inner = (@entries[context] ||= {})

          if (entry = inner.fetch(type_name, nil))
            result, names = entry
            @current&.concat(names)
            return result
          end

          outer = @current
          names = [] #: Array[RBS::TypeName]
          @current = names

          begin
            result = yield
            inner[type_name] = [result, names]
            result
          ensure
            @current = outer
            outer&.concat(names)
          end
        end
      end

      attr_reader :probes

      attr_reader :wildcards

      def initialize(probes: {}, wildcards: {})
        @probes = probes
        @wildcards = wildcards
      end

      def resolve(env, paths: nil)
        resolver = Resolver.build(env)

        table = RBS::Environment::UseMap::Table.new()
        table.known_types.merge(env.class_decls.keys)
        table.known_types.merge(env.class_alias_decls.keys)
        table.known_types.merge(env.type_alias_decls.keys)
        table.known_types.merge(env.interface_decls.keys)
        table.compute_children

        new_wildcards = {} #: Hash[Pathname, Array[RBS::Namespace]]
        new_env = RBS::Environment.new

        env.each_rbs_source do |source|
          path = source.buffer.name

          if paths && !paths.include?(path)
            new_env.add_source(source)
            next
          end

          resolve = source.directives.find { _1.is_a?(RBS::AST::Directives::ResolveTypeNames) } #: RBS::AST::Directives::ResolveTypeNames?
          if resolve && !resolve.value
            new_env.add_source(source)
            next
          end

          resolver.record(path) do
            source.directives.each do |directive|
              next unless directive.is_a?(RBS::AST::Directives::Use)
              directive.clauses.each do |clause|
                if clause.is_a?(RBS::AST::Directives::Use::WildcardClause)
                  (new_wildcards[path] ||= []) << clause.namespace.absolute!
                end
              end
            end

            _, decls = env.resolve_signature(resolver, table, source.directives, source.declarations)
            new_env.add_source(RBS::Source::RBS.new(source.buffer, source.directives, decls))
          end
        end

        env.each_ruby_source do |source|
          path = source.buffer.name

          if paths && !paths.include?(path)
            new_env.add_source(source)
            next
          end

          resolver.record(path) do
            decls = source.declarations.map do |decl|
              # The method is public, but declared private in the RBS of RBS
              (_ = env).resolve_ruby_decl(resolver, decl, context: nil, prefix: RBS::Namespace.root) #: RBS::AST::Ruby::Declarations::t
            end
            new_env.add_source(RBS::Source::Ruby.new(source.buffer, source.prism_result, decls, source.diagnostics))
          end
        end

        if paths
          probes = self.probes.reject { |path, _| paths.include?(path) }
          wildcards = self.wildcards.reject { |path, _| paths.include?(path) }
        else
          probes = {} #: Hash[Pathname, Set[RBS::TypeName]]
          wildcards = {} #: Hash[Pathname, Array[RBS::Namespace]]
        end

        probes.merge!(resolver.probes)
        wildcards.merge!(new_wildcards)

        [new_env, TypeNameResolution.new(probes: probes, wildcards: wildcards)]
      end

      def affected_paths(old_env, new_env, except:)
        names = changed_names(old_env, new_env)
        return Set[] if names.empty?

        namespaces = Set.new(names.map(&:namespace))
        affected = Set[] #: Set[Pathname]

        probes.each do |path, probed|
          next if except.include?(path)
          affected << path if probed.intersect?(names)
        end

        wildcards.each do |path, nss|
          next if except.include?(path)
          affected << path if nss.any? { namespaces.include?(_1) }
        end

        affected
      end

      def changed_names(old_env, new_env)
        names = Set[] #: Set[RBS::TypeName]

        add_key_changes(old_env.class_decls, new_env.class_decls, names)
        add_key_changes(old_env.class_alias_decls, new_env.class_alias_decls, names)
        add_key_changes(old_env.interface_decls, new_env.interface_decls, names)
        add_key_changes(old_env.type_alias_decls, new_env.type_alias_decls, names)

        new_env.class_alias_decls.each do |name, entry|
          if old_entry = old_env.class_alias_decls.fetch(name, nil)
            names << name unless old_entry.decl.equal?(entry.decl)
          end
        end

        names
      end

      def add_key_changes(old_decls, new_decls, names)
        old_decls.each_key { names << _1 unless new_decls.key?(_1) }
        new_decls.each_key { names << _1 unless old_decls.key?(_1) }
      end
    end
  end
end
