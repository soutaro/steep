module Steep
  class Project
    class DSL
      module LibraryOptions
        attr_reader :stdlib_root
        attr_reader :core_root
        attr_reader :collection_config_path

        def stdlib_path(core_root:, stdlib_root:)
          @core_root = Pathname(core_root)
          @stdlib_root = Pathname(stdlib_root)
        end

        def repo_path(*paths)
          @library_configured = true
          repo_paths.push(*paths.map {|s| Pathname(s) })
        end

        def collection_config(path)
          @library_configured = true
          @collection_config_path = project.absolute_path(path)
        end

        def disable_collection
          @library_configured = true
          @collection_config_path = false
        end

        def library(*args)
          @library_configured = true
          libraries.push(*args)
        end

        def repo_paths
          @repo_paths ||= []
        end

        def libraries
          @libraries ||= []
        end

        def library_configured?
          @library_configured
        end

        def to_library_options
          config_path =
            case collection_config_path
            when Pathname
              collection_config_path
            when nil
              default = project.absolute_path(RBS::Collection::Config::PATH)
              if default.file?
                default
              end
            when false
              nil
            end

          Options.new.tap do |options|
            options.libraries.push(*libraries)
            options.paths = Options::PathOptions.new(
              core_root: core_root,
              stdlib_root: stdlib_root,
              repo_paths: repo_paths
            )
            options.collection_config_path = config_path
          end
        end
      end

      module WithPattern
        def check(*args)
          sources.concat(args)
        end

        def ignore(*args)
          ignored_sources.concat(args)
        end

        def signature(*args)
          signatures.concat(args)
        end

        def ignore_signature(*args)
          ignored_signatures.concat(args)
        end

        def sources
          @sources ||= []
        end

        def ignored_sources
          @ignored_sources ||= []
        end

        def signatures
          @signatures ||= []
        end

        def ignored_signatures
          @ignored_signatures ||= []
        end

        def source_pattern
          Pattern.new(patterns: sources, ignores: ignored_sources, ext: ".rb")
        end

        def signature_pattern
          Pattern.new(patterns: signatures, ignores: ignored_signatures, ext: ".rbs")
        end
      end

      class TargetDSL
        include LibraryOptions
        include WithPattern

        attr_reader :name
        attr_reader :project
        attr_reader :unreferenced
        attr_reader :groups
        attr_reader :implicitly_returns_nil

        def initialize(name, project:)
          @name = name
          @core_root = nil
          @stdlib_root = nil
          @project = project
          @collection_config_path = collection_config_path
          @unreferenced = false
          @implicitly_returns_nil = false
          @groups = []
        end

        def initialize_copy(other)
          @name = other.name
          @libraries = other.libraries.dup
          @sources = other.sources.dup
          @signatures = other.signatures.dup
          @ignored_sources = other.ignored_sources.dup
          @ignored_signatures = other.ignored_signatures.dup
          @repo_paths = other.repo_paths.dup
          @core_root = other.core_root
          @stdlib_root = other.stdlib_root
          @code_diagnostics_config = other.code_diagnostics_config.dup
          @project = other.project
          @collection_config_path = other.collection_config_path
          @unreferenced = other.unreferenced
          @implicitly_returns_nil = other.implicitly_returns_nil
          @groups = other.groups.dup
        end

        def unreferenced!(value = true)
          @unreferenced = value
        end

        def implicitly_returns_nil!(value = true)
          @implicitly_returns_nil = value
        end

        def configure_code_diagnostics(hash = nil)
          if hash
            code_diagnostics_config.merge!(hash)
          end

          yield code_diagnostics_config if block_given?
        end

        def code_diagnostics_config
          @code_diagnostics_config ||= Diagnostic::Ruby.default.dup
        end

        def group(name, &block)
          name = name.to_str.to_sym unless Symbol === name
          group = GroupDSL.new(name, self)

          Steep.logger.tagged "group=#{name}" do
            group.instance_exec(&block) if block
          end

          groups << group
        end
      end

      class GroupDSL
        include WithPattern

        attr_reader :name

        attr_reader :target

        attr_reader :code_diagnostics_config

        def initialize(name, target)
          @name = name
          @target = target
        end

        def configure_code_diagnostics(config = nil)
          if block_given?
            if code_diagnostics_config
              if config
                code_diagnostics_config.merge!(config)
              end
            else
              @code_diagnostics_config = (config || target.code_diagnostics_config).dup
            end

            yield (code_diagnostics_config || raise)
          else
            @code_diagnostics_config = config&.dup
          end
        end
      end

      include LibraryOptions

      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def self.parse(project, code, filename: "Steepfile")
        Steep.logger.tagged filename do
          dsl = self.new(project: project)
          dsl.instance_eval(code, filename)
          project.global_options = dsl.to_library_options
        end
      end

      def self.eval(project, &block)
        Steep.logger.tagged "DSL.eval" do
          dsl = self.new(project: project)
          dsl.instance_exec(&block)
          project.global_options = dsl.to_library_options
        end
      end

      def target(name, &block)
        name = name.to_str.to_sym unless Symbol === name
        dsl = TargetDSL.new(name, project: project)

        Steep.logger.tagged "target=#{name}" do
          dsl.instance_eval(&block) if block
        end

        target = Project::Target.new(
          name: dsl.name,
          source_pattern: dsl.source_pattern,
          signature_pattern: dsl.signature_pattern,
          options: dsl.library_configured? ? dsl.to_library_options : nil,
          code_diagnostics_config: dsl.code_diagnostics_config,
          project: project,
          unreferenced: dsl.unreferenced,
          implicitly_returns_nil: dsl.implicitly_returns_nil
        )

        dsl.groups.each do
          group = Group.new(target, _1.name, _1.source_pattern, _1.signature_pattern, _1.code_diagnostics_config || target.code_diagnostics_config)
          target.groups << group
        end

        project.targets << target
      end
    end
  end
end
