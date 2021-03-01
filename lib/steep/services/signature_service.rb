module Steep
  module Services
    class SignatureService
      attr_reader :status

      class SyntaxErrorStatus
        attr_reader :files, :changed_paths, :diagnostics, :last_builder

        def initialize(files:, changed_paths:, diagnostics:, last_builder:)
          @files = files
          @changed_paths = changed_paths
          @diagnostics = diagnostics
          @last_builder = last_builder
        end
      end

      class AncestorErrorStatus
        attr_reader :files, :changed_paths, :diagnostics, :last_builder

        def initialize(files:, changed_paths:, diagnostics:, last_builder:)
          @files = files
          @changed_paths = changed_paths
          @diagnostics = diagnostics
          @last_builder = last_builder
        end
      end

      class LoadedStatus
        attr_reader :files, :builder

        def initialize(files:, builder:)
          @files = files
          @builder = builder
        end

        def subtyping
          @subtyping ||= Subtyping::Check.new(factory: AST::Types::Factory.new(builder: builder))
        end
      end

      FileStatus = Struct.new(:path, :content, :decls, keyword_init: true)

      def initialize(env:)
        builder = RBS::DefinitionBuilder.new(env: env)
        @status = LoadedStatus.new(builder: builder, files: {})
      end

      def self.load_from(loader)
        env = RBS::Environment.from_loader(loader).resolve_type_names
        new(env: env)
      end

      def each_rbs_path(&block)
        if block
          latest_env.buffers.each do |buffer|
            unless files.key?(buffer.name)
              yield Pathname(buffer.name)
            end
          end

          files.each_key(&block)
        else
          enum_for :each_rbs_path
        end
      end

      def files
        status.files
      end

      def pending_changed_paths
        case status
        when LoadedStatus
          Set[]
        when SyntaxErrorStatus, AncestorErrorStatus
          Set.new(status.changed_paths)
        end
      end

      def latest_env
        latest_builder.env
      end

      def latest_builder
        case status
        when LoadedStatus
          status.builder
        when SyntaxErrorStatus, AncestorErrorStatus
          status.last_builder
        end
      end

      def current_subtyping
        if status.is_a?(LoadedStatus)
          status.subtyping
        end
      end

      def apply_changes(files, changes)
        changes.each.with_object({}) do |(path, cs), update|
          old_text = files[path]&.content
          content = cs.inject(old_text || "") {|text, change| change.apply_to(text) }

          buffer = RBS::Buffer.new(name: path, content: content)

          update[path] = begin
                           FileStatus.new(path: path, content: content, decls: RBS::Parser.parse_signature(buffer))
                         rescue RBS::ParsingError => exn
                           FileStatus.new(path: path, content: content, decls: exn)
                         end
        end
      end

      def update(changes)
        updates = apply_changes(files, changes)
        paths = Set.new(updates.each_key)
        paths.merge(pending_changed_paths)

        if updates.each_value.any? {|file| file.decls.is_a?(RBS::ParsingError) }
          diagnostics = []

          updates.each do |path, file|
            if file.decls.is_a?(RBS::ParsingError)
              # facotry is not used here because the error is a syntax error.
              diagnostics << Diagnostic::Signature.from_rbs_error(file.decls, factory: nil)
            end
          end

          @status = SyntaxErrorStatus.new(
            files: self.files.merge(updates),
            diagnostics: diagnostics,
            last_builder: latest_builder,
            changed_paths: paths
          )
        else
          files = self.files.merge(updates)
          updated_files = paths.each.with_object({}) do |path, hash|
            hash[path] = files[path]
          end
          result = update_env(updated_files, paths: paths)

          @status = case result
                    when Array
                      AncestorErrorStatus.new(
                        changed_paths: paths,
                        last_builder: latest_builder,
                        diagnostics: result,
                        files: files
                      )
                    when RBS::DefinitionBuilder::AncestorBuilder
                      LoadedStatus.new(builder: update_builder(ancestor_builder: result, paths: paths), files: files)
                    end
        end
      end

      def update_env(updated_files, paths:)
        errors = []

        env = latest_env.reject do |decl|
          if decl.location
            paths.include?(decl.location.buffer.name)
          end
        end

        updated_files.each_value do |content|
          if content.decls.is_a?(RBS::ErrorBase)
            errors << content.decls
          else
            begin
              content.decls.each do |decl|
                env << decl
              end
            rescue RBS::LoadingError => exn
              errors << exn
            end
          end
        end

        begin
          env.validate_type_params
        rescue RBS::LoadingError => exn
          errors << exn
        end

        unless errors.empty?
          return errors.map {|error|
            # Factory will not be used because of the possible error types.
            Diagnostic::Signature.from_rbs_error(error, factory: nil)
          }
        end

        builder = RBS::DefinitionBuilder::AncestorBuilder.new(env: env.resolve_type_names)
        builder.env.class_decls.each_key do |type_name|
          rescue_rbs_error(errors) { builder.one_instance_ancestors(type_name) }
          rescue_rbs_error(errors) { builder.one_singleton_ancestors(type_name) }
        end
        builder.env.interface_decls.each_key do |type_name|
          rescue_rbs_error(errors) { builder.one_interface_ancestors(type_name) }
        end

        unless errors.empty?
          # Builder won't be used.
          factory = AST::Types::Factory.new(builder: nil)
          return errors.map {|error| Diagnostic::Signature.from_rbs_error(error, factory: factory) }
        end

        builder
      end

      def rescue_rbs_error(errors)
        begin
          yield
        rescue RBS::ErrorBase => exn
          errors << exn
        end
      end

      def update_builder(ancestor_builder:, paths:)
        changed_names = Set[]

        old_definition_builder = latest_builder
        old_env = old_definition_builder.env
        old_names = type_names(paths: paths, env: old_env)
        old_ancestor_builder = old_definition_builder.ancestor_builder
        old_method_builder = old_definition_builder.method_builder
        old_graph = RBS::AncestorGraph.new(env: old_env, ancestor_builder: old_ancestor_builder)
        add_descendants(graph: old_graph, names: old_names, set: changed_names)
        add_nested_decls(env: old_env, names: old_names, set: changed_names)

        new_env = ancestor_builder.env
        new_ancestor_builder = ancestor_builder
        new_names = type_names(paths: paths, env: new_env)
        new_graph = RBS::AncestorGraph.new(env: new_env, ancestor_builder: new_ancestor_builder)
        add_descendants(graph: new_graph, names: new_names, set: changed_names)
        add_nested_decls(env: new_env, names: new_names, set: changed_names)

        old_definition_builder.update(
          env: new_env,
          ancestor_builder: new_ancestor_builder,
          except: changed_names
        )
      end

      def type_names(paths:, env:)
        env.declarations.each.with_object(Set[]) do |decl, set|
          if decl.location
            if paths.include?(decl.location.buffer.name)
              type_name_from_decl(decl, set: set)
            end
          end
        end
      end

      def type_name_from_decl(decl, set:)
        case decl
        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface
          set << decl.name

          decl.members.each do |member|
            if member.is_a?(RBS::AST::Declarations::Base)
              type_name_from_decl(member, set: set)
            end
          end
        when RBS::AST::Declarations::Alias
          set << decl.name
        end
      end

      def add_descendants(graph:, names:, set:)
        set.merge(names)
        names.each do |name|
          case
          when name.interface?
            graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
              set << node.type_name
            end
          when name.class?
            graph.each_descendant(RBS::AncestorGraph::InstanceNode.new(type_name: name)) do |node|
              set << node.type_name
            end
            graph.each_descendant(RBS::AncestorGraph::SingletonNode.new(type_name: name)) do |node|
              set << node.type_name
            end
          end
        end
      end

      def add_nested_decls(env:, names:, set:)
        tops = names.each.with_object(Set[]) do |name, tops|
          unless name.namespace.empty?
            tops << name.namespace.path[0]
          end
        end

        env.class_decls.each_key do |name|
          unless name.namespace.empty?
            if tops.include?(name.namespace.path[0])
              set << name
            end
          end
        end

        env.interface_decls.each_key do |name|
          unless name.namespace.empty?
            if tops.include?(name.namespace.path[0])
              set << name
            end
          end
        end
      end
    end
  end
end
