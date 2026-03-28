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
        attr_reader :files, :changed_paths, :diagnostics, :last_builder, :implicitly_returns_nil

        def initialize(files:, changed_paths:, diagnostics:, last_builder:, implicitly_returns_nil:)
          @files = files
          @changed_paths = changed_paths
          @diagnostics = diagnostics
          @last_builder = last_builder
          @implicitly_returns_nil = implicitly_returns_nil
        end

        def subtyping
          @subtyping ||= begin
            factory = AST::Types::Factory.new(builder: last_builder)
            interface_builder = Interface::Builder.new(factory, implicitly_returns_nil: implicitly_returns_nil)
            Subtyping::Check.new(builder: interface_builder)
          end
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
        attr_reader :files, :builder, :implicitly_returns_nil

        def initialize(files:, builder:, implicitly_returns_nil:)
          @files = files
          @builder = builder
          @implicitly_returns_nil = implicitly_returns_nil
        end

        def subtyping
          @subtyping ||= begin
            factory = AST::Types::Factory.new(builder: builder)
            interface_builder = Interface::Builder.new(factory, implicitly_returns_nil: implicitly_returns_nil)
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

      RBSFileStatus = _ = Struct.new(:path, :content, :source, keyword_init: true)

      attr_reader :implicitly_returns_nil

      def initialize(env:, implicitly_returns_nil:)
        builder = RBS::DefinitionBuilder.new(env: env)
        @status = LoadedStatus.new(builder: builder, files: {}, implicitly_returns_nil: implicitly_returns_nil)
        @implicitly_returns_nil = implicitly_returns_nil
      end

      def self.load_from(loader, implicitly_returns_nil:)
        env = RBS::Environment.from_loader(loader).resolve_type_names
        new(env: env, implicitly_returns_nil: implicitly_returns_nil)
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
        case status = status()
        when LoadedStatus, AncestorErrorStatus
          status.subtyping
        end
      end

      def apply_changes(files, changes)
        Steep.logger.tagged "#apply_changes" do
          Steep.measure2 "Applying change" do |sampler|
            changes.each.with_object({}) do |(path, cs), update|  # $ Hash[Pathname, file_status]
              sampler.sample "#{path}" do
                old_file = files.fetch(path, nil)

                case old_file
                when RBSFileStatus
                  old_text = old_file.content
                  new_file = load_rbs_file(path, old_text, cs)
                when RBS::Source::Ruby
                  old_text = old_file.buffer.content
                  new_file = load_ruby_file(path, old_text, cs)
                when nil
                  # New file: Detect based on the file name
                  if path.extname == ".rbs"
                    # RBS File
                    new_file = load_rbs_file(path, "", cs)
                  else
                    # Ruby File
                    new_file = load_ruby_file(path, "", cs)
                  end
                end

                update[path] = new_file
              end
            end
          end
        end
      end

      def load_rbs_file(path, old_text, changes)
        content = changes.reduce(old_text) do |text, change| # $ String
          change.apply_to(text)
        end

        buffer = RBS::Buffer.new(name: path, content: content)
        source =
          begin
            _, dirs, decls = RBS::Parser.parse_signature(buffer)
            RBS::Source::RBS.new(buffer, dirs, decls)
          rescue ArgumentError => exn
            Diagnostic::Signature::UnexpectedError.new(
              message: exn.message,
              location: RBS::Location.new(buffer: buffer, start_pos: 0, end_pos: content.size)
            )
          rescue RBS::ParsingError => exn
            exn
          end

        RBSFileStatus.new(path: path, content: content, source: source)
      end

      def load_ruby_file(path, old_text, changes)
        content = changes.reduce(old_text) do |text, change| # $ String
          change.apply_to(text)
        end

        buffer = RBS::Buffer.new(name: path, content: content)
        prism = Prism.parse(buffer.content, filepath: path.to_s)
        result = RBS::InlineParser.parse(buffer, prism)
        RBS::Source::Ruby.new(buffer, prism, result.declarations, result.diagnostics)
      end

      def error_file?(file)
        case file
        when RBSFileStatus
          !file.source.is_a?(RBS::Source::RBS)
        when RBS::Source::Ruby
          false
        end
      end

      def update(changes)
        Steep.logger.tagged "#update" do
          updates = apply_changes(files, changes)
          paths = Set.new(updates.each_key)
          paths.merge(pending_changed_paths)

          if updates.each_value.any? {|file| error_file?(file) }
            diagnostics = [] #: Array[Diagnostic::Signature::Base]

            updates.each_value do |file|
              if error_file?(file)
                if file.is_a?(RBSFileStatus)
                  diagnostic =
                    case file.source
                    when Diagnostic::Signature::Base
                      file.source
                    when RBS::ParsingError
                      Diagnostic::Signature.from_rbs_error(file.source, factory: _ = nil)
                    else
                      raise "file (#{file.path}) must be an error"
                    end

                  diagnostics << diagnostic
                end
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
                        diagnostics, definition_builder = result
                        AncestorErrorStatus.new(
                          changed_paths: paths,
                          last_builder: definition_builder,
                          diagnostics: diagnostics,
                          files: files,
                          implicitly_returns_nil: implicitly_returns_nil
                        )
                      when RBS::DefinitionBuilder::AncestorBuilder
                        builder2 = update_builder(ancestor_builder: result, paths: paths)
                        LoadedStatus.new(builder: builder2, files: files, implicitly_returns_nil: implicitly_returns_nil)
                      end
          end
        end
      end

      def update_env(updated_files, paths:)
        Steep.logger.tagged "#update_env" do
          errors = [] #: Array[RBS::BaseError]
          new_decls = Set[].compare_by_identity #: Set[RBS::AST::Declarations::t | RBS::AST::Ruby::Declarations::t]

          env =
            Steep.measure "Deleting out of date decls" do
              latest_env.unload(paths)
            end

          Steep.measure "Loading new decls" do
            updated_files.each_value do |content|
              case content
              when RBSFileStatus
                (source = content.source).is_a?(RBS::Source::RBS) or raise "Cannot be an error"
                env.add_source(source)
                new_decls.merge(source.declarations)
              when RBS::Source::Ruby
                env.add_source(content)
                new_decls.merge(content.declarations)
              end
            rescue RBS::LoadingError => exn
              errors << exn
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
            diagnostics = errors.map {|error|
              # Factory will not be used because of the possible error types.
              Diagnostic::Signature.from_rbs_error(error, factory: _ = nil)
            }
            definition_builder = RBS::DefinitionBuilder.new(env: env)
            return [diagnostics, definition_builder]
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
            errors.uniq! { |e| [e.class, e.message] }
            definition_builder = RBS::DefinitionBuilder.new(env: env, ancestor_builder: builder)
            factory = AST::Types::Factory.new(builder: definition_builder)
            return [errors.map {|error| Diagnostic::Signature.from_rbs_error(error, factory: factory) }, definition_builder]
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

        Hash.new {}
        set = Set[] #: Set[RBS::TypeName]

        env.each_rbs_source do |source|
          next unless paths.include?(source.buffer.name)
          source.each_type_name do |type_name|
            set << type_name
          end
        end

        env.each_ruby_source do |source|
          next unless paths.include?(source.buffer.name)
          source.each_type_name do |type_name|
            set << type_name
          end
        end

        set
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
