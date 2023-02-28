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

        def rbs_index
          @rbs_index ||= Index::RBSIndex.new().tap do |index|
            builder = Index::RBSIndex::Builder.new(index: index)
            builder.env(last_builder.env)
          end
        end

        def constant_resolver
          @constant_resolver ||= RBS::Resolver::ConstantResolver.new(builder: last_builder)
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

        def rbs_index
          @rbs_index ||= Index::RBSIndex.new().tap do |index|
            builder = Index::RBSIndex::Builder.new(index: index)
            builder.env(last_builder.env)
          end
        end

        def constant_resolver
          @constant_resolver ||= RBS::Resolver::ConstantResolver.new(builder: last_builder)
        end
      end

      class LoadedStatus
        attr_reader :files, :builder

        def initialize(files:, builder:)
          @files = files
          @builder = builder
        end

        def subtyping
          @subtyping ||= begin
            factory = AST::Types::Factory.new(builder: builder)
            interface_builder = Interface::Builder.new(factory)
            Subtyping::Check.new(builder: interface_builder)
          end
        end

        def rbs_index
          @rbs_index ||= Index::RBSIndex.new().tap do |index|
            builder = Index::RBSIndex::Builder.new(index: index)
            builder.env(self.builder.env)
          end
        end

        def constant_resolver
          @constant_resolver ||= RBS::Resolver::ConstantResolver.new(builder: builder)
        end
      end

      FileStatus = _ = Struct.new(:path, :content, :signature, keyword_init: true)

      def initialize(env:)
        builder = RBS::DefinitionBuilder.new(env: env)
        @status = LoadedStatus.new(builder: builder, files: {})
      end

      def self.load_from(loader)
        env = RBS::Environment.from_loader(loader).resolve_type_names
        new(env: env)
      end

      def env_rbs_paths
        @env_rbs_paths ||= latest_env.buffers.each.with_object(Set[]) do |buffer, set|
          set << Pathname(buffer.name)
        end
      end

      def each_rbs_path(&block)
        if block
          env_rbs_paths.each do |path|
            unless files.key?(path)
              yield path
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
        case status = status()
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
        case status = status()
        when LoadedStatus
          status.builder
        when SyntaxErrorStatus, AncestorErrorStatus
          status.last_builder
        end
      end

      def latest_rbs_index
        status.rbs_index
      end

      def latest_constant_resolver
        status.constant_resolver
      end

      def current_subtyping
        if status.is_a?(LoadedStatus)
          status.subtyping
        end
      end

      def apply_changes(files, changes)
        Steep.logger.tagged "#apply_changes" do
          Steep.measure2 "Applying change" do |sampler|
            changes.each.with_object({}) do |pair, update|  # $ Hash[Pathname, FileStatus]
              path, cs = pair
              sampler.sample "#{path}" do
                old_text = files[path]&.content
                content = cs.inject(old_text || "") {|text, change| change.apply_to(text) }

                buffer = RBS::Buffer.new(name: path, content: content)

                update[path] =
                  begin
                    FileStatus.new(path: path, content: content, signature: RBS::Parser.parse_signature(buffer))
                  rescue ArgumentError => exn
                    error = Diagnostic::Signature::UnexpectedError.new(
                      message: exn.message,
                      location: RBS::Location.new(buffer: buffer, start_pos: 0, end_pos: content.size)
                    )
                    FileStatus.new(path: path, content: content, signature: error)
                  rescue RBS::ParsingError => exn
                    FileStatus.new(path: path, content: content, signature: exn)
                  end
              end
            end
          end
        end
      end

      def update(changes)
        Steep.logger.tagged "#update" do
          updates = apply_changes(files, changes)
          paths = Set.new(updates.each_key)
          paths.merge(pending_changed_paths)

          if updates.each_value.any? {|file| !file.signature.is_a?(Array) }
            diagnostics = [] #: Array[Diagnostic::Signature::Base]

            updates.each_value do |file|
              unless file.signature.is_a?(Array)
                diagnostic = if file.signature.is_a?(Diagnostic::Signature::Base)
                               file.signature
                             else
                               # factory is not used here because the error is a syntax error.
                               Diagnostic::Signature.from_rbs_error(file.signature, factory: _ = nil)
                             end
                diagnostics << diagnostic
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
            updated_files = files.slice(*paths.to_a)
            result =
              Steep.measure "#update_env with updated #{paths.size} files" do
                update_env(updated_files, paths: paths)
              end

            @status = case result
                      when Array
                        AncestorErrorStatus.new(
                          changed_paths: paths,
                          last_builder: latest_builder,
                          diagnostics: result,
                          files: files
                        )
                      when RBS::DefinitionBuilder::AncestorBuilder
                        builder2 = update_builder(ancestor_builder: result, paths: paths)
                        LoadedStatus.new(builder: builder2, files: files)
                      end
          end
        end
      end

      def update_env(updated_files, paths:)

        Steep.logger.tagged "#update_env" do
          errors = [] #: Array[RBS::BaseError]
          new_decls = Set[].compare_by_identity #: Set[RBS::AST::Declarations::t]

          env =
            Steep.measure "Deleting out of date decls" do
              bufs = latest_env.buffers.select {|buf| paths.include?(buf.name) }
              latest_env.unload(Set.new(bufs))
            end

          Steep.measure "Loading new decls" do
            updated_files.each_value do |content|
              case content.signature
              when RBS::ParsingError
                errors << content.signature
              when Diagnostic::Signature::UnexpectedError
                return [content.signature]
              else
                begin
                  buffer, dirs, decls = content.signature
                  env.add_signature(buffer: buffer, directives: dirs, decls: decls)
                  new_decls.merge(decls)
                rescue RBS::LoadingError => exn
                  errors << exn
                end
              end
            end
          end

          Steep.measure "validate type params" do
            begin
              env.validate_type_params
            rescue RBS::LoadingError => exn
              errors << exn
            end
          end

          unless errors.empty?
            return errors.map {|error|
              # Factory will not be used because of the possible error types.
              Diagnostic::Signature.from_rbs_error(error, factory: _ = nil)
            }
          end

          Steep.measure "resolve type names with #{new_decls.size} top-level decls" do
            env = env.resolve_type_names(only: new_decls)
          end

          builder = RBS::DefinitionBuilder::AncestorBuilder.new(env: env)

          Steep.measure("Pre-loading one ancestors") do
            builder.env.class_decls.each_key do |type_name|
              rescue_rbs_error(errors) { builder.one_instance_ancestors(type_name) }
              rescue_rbs_error(errors) { builder.one_singleton_ancestors(type_name) }
            end
            builder.env.interface_decls.each_key do |type_name|
              rescue_rbs_error(errors) { builder.one_interface_ancestors(type_name) }
            end
          end

          unless errors.empty?
            # Builder won't be used.
            factory = AST::Types::Factory.new(builder: _ = nil)
            return errors.map {|error| Diagnostic::Signature.from_rbs_error(error, factory: factory) }
          end

          builder
        end
      end

      def rescue_rbs_error(errors)
        begin
          yield
        rescue RBS::BaseError => exn
          errors << exn
        end
      end

      def update_builder(ancestor_builder:, paths:)
        Steep.measure "#update_builder with #{paths.size} files" do
          changed_names = Set[]

          old_definition_builder = latest_builder
          old_env = old_definition_builder.env
          old_names = type_names(paths: paths, env: old_env)
          old_ancestor_builder = old_definition_builder.ancestor_builder
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
      end

      def type_names(paths:, env:)
        env.declarations.each.with_object(Set[]) do |decl, set|
          if decl.location
            if paths.include?(Pathname(decl.location.buffer.name))
              type_name_from_decl(decl, set: set)
            end
          end
        end
      end

      def const_decls(paths:, env:)
        env.constant_decls.filter do |_, entry|
          if location = entry.decl.location
            paths.include?(Pathname(location.buffer.name))
          end
        end
      end

      def global_decls(paths:, env: latest_env)
        env.global_decls.filter do |_, entry|
          if location = entry.decl.location
            paths.include?(Pathname(location.buffer.name))
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
        when RBS::AST::Declarations::TypeAlias
          set << decl.name
        when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
          set << decl.new_name
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
        tops = names.each_with_object(Set[]) do |name, tops|
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
