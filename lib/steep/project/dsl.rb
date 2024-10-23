module Steep
  class Project
    class DSL
      class TargetDSL
        attr_reader :name
        attr_reader :sources
        attr_reader :libraries
        attr_reader :signatures
        attr_reader :ignored_sources
        attr_reader :stdlib_root
        attr_reader :core_root
        attr_reader :repo_paths
        attr_reader :code_diagnostics_config
        attr_reader :project
        attr_reader :collection_config_path

        def initialize(name, sources: [], libraries: [], signatures: [], ignored_sources: [], repo_paths: [], code_diagnostics_config: {}, project:, collection_config_path: nil)
          @name = name
          @sources = sources
          @libraries = libraries
          @signatures = signatures
          @ignored_sources = ignored_sources
          @core_root = nil
          @stdlib_root = nil
          @repo_paths = []
          @code_diagnostics_config = code_diagnostics_config
          @project = project
          @collection_config_path = collection_config_path
        end

        def initialize_copy(other)
          @name = other.name
          @sources = other.sources.dup
          @libraries = other.libraries.dup
          @signatures = other.signatures.dup
          @ignored_sources = other.ignored_sources.dup
          @repo_paths = other.repo_paths.dup
          @core_root = other.core_root
          @stdlib_root = other.stdlib_root
          @code_diagnostics_config = other.code_diagnostics_config.dup
          @project = other.project
          @collection_config_path = other.collection_config_path
        end

        def check(*args)
          sources.push(*args)
        end

        def ignore(*args)
          ignored_sources.push(*args)
        end

        def library(*args)
          libraries.push(*args)
        end

        def signature(*args)
          signatures.push(*args)
        end

        def stdlib_path(core_root:, stdlib_root:)
          @core_root = Pathname(core_root)
          @stdlib_root = Pathname(stdlib_root)
        end

        def repo_path(*paths)
          @repo_paths.push(*paths.map {|s| Pathname(s) })
        end

        def configure_code_diagnostics(hash = nil)
          if hash
            code_diagnostics_config.merge!(hash)
          end

          yield code_diagnostics_config if block_given?
        end

        def collection_config(path)
          @collection_config_path = project.absolute_path(path)
        end

        def disable_collection
          @collection_config_path = false
        end
      end

      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def self.parse(project, code, filename: "Steepfile")
        Steep.logger.tagged filename do
          self.new(project: project).instance_eval(code, filename)
        end
      end

      def target(name, &block)
        target = TargetDSL.new(name, code_diagnostics_config: Diagnostic::Ruby.default.dup, project: project)

        Steep.logger.tagged "target=#{name}" do
          target.instance_eval(&block) if block
        end

        source_pattern = Pattern.new(patterns: target.sources, ignores: target.ignored_sources, ext: ".rb")
        signature_pattern = Pattern.new(patterns: target.signatures, ext: ".rbs")

        config_path =
          case target.collection_config_path
          when Pathname
            target.collection_config_path
          when nil
            default = project.absolute_path(RBS::Collection::Config::PATH)
            if default.file?
              default
            end
          when false
            nil
          end

        Project::Target.new(
          name: target.name,
          source_pattern: source_pattern,
          signature_pattern: signature_pattern,
          options: Options.new.tap do |options|
            options.libraries.push(*target.libraries)
            options.paths = Options::PathOptions.new(
              core_root: target.core_root,
              stdlib_root: target.stdlib_root,
              repo_paths: target.repo_paths
            )
            options.collection_config_path = config_path
          end,
          code_diagnostics_config: target.code_diagnostics_config
        ).tap do |target|
          project.targets << target
        end
      end
    end
  end
end
