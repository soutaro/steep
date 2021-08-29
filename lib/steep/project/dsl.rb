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

        def initialize(name, sources: [], libraries: [], signatures: [], ignored_sources: [], repo_paths: [], code_diagnostics_config: {})
          @name = name
          @sources = sources
          @libraries = libraries
          @signatures = signatures
          @ignored_sources = ignored_sources
          @core_root = nil
          @stdlib_root = nil
          @repo_paths = []
          @code_diagnostics_config = code_diagnostics_config
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

        def typing_options(level = nil, **hash)
          Steep.logger.error "#typing_options is deprecated and has no effect as of version 0.46.0"
        end

        def signature(*args)
          signatures.push(*args)
        end

        def update(name: self.name, sources: self.sources, libraries: self.libraries, ignored_sources: self.ignored_sources, signatures: self.signatures)
          self.class.new(
            name,
            sources: sources,
            libraries: libraries,
            signatures: signatures,
            ignored_sources: ignored_sources
          )
        end

        def no_builtin!(value = true)
          Steep.logger.error "`#no_builtin!` in Steepfile is deprecated and ignored. Use `#stdlib_path` instead."
        end

        def vendor(dir = "vendor/sigs", stdlib: nil, gems: nil)
          Steep.logger.error "`#vendor` in Steepfile is deprecated and ignored. Use `#stdlib_path` instead."
        end

        def stdlib_path(core_root:, stdlib_root:)
          @core_root = core_root ? Pathname(core_root) : core_root
          @stdlib_root = stdlib_root ? Pathname(stdlib_root) : stdlib_root
        end

        def repo_path(*paths)
          @repo_paths.push(*paths.map {|s| Pathname(s) })
        end

        # Configure the code diagnostics printing setup.
        #
        # Yields a hash, and the update the hash in the block.
        #
        # ```rb
        # D = Steep::Diagnostic
        #
        # configure_code_diagnostics do |hash|
        #   # Assign one of :error, :warning, :information, :hint or :nil to error classes.
        #   hash[D::Ruby::UnexpectedPositionalArgument] = :error
        # end
        # ```
        #
        # Passing a hash is also allowed.
        #
        # ```rb
        # D = Steep::Diagnostic
        #
        # configure_code_diagnostics(D::Ruby.lenient)
        # ```
        #
        def configure_code_diagnostics(hash = nil)
          if hash
            code_diagnostics_config.merge!(hash)
          end

          yield code_diagnostics_config if block_given?
        end
      end

      attr_reader :project

      @@templates = {
        gemfile: TargetDSL.new(:gemfile).tap do |target|
          target.check "Gemfile"
          target.library "gemfile"
        end
      }

      def self.templates
        @@templates
      end

      def initialize(project:)
        @project = project
        @global_signatures = []
      end

      def self.register_template(name, target)
        templates[name] = target
      end

      def self.parse(project, code, filename: "Steepfile")
        Steep.logger.tagged filename do
          self.new(project: project).instance_eval(code, filename)
        end
      end

      def target(name, template: nil, &block)
        target = if template
                   self.class.templates[template]&.dup&.update(name: name) or
                     raise "Unknown template: #{template}, available templates: #{@@templates.keys.join(", ")}"
                 else
                   TargetDSL.new(name, code_diagnostics_config: Diagnostic::Ruby.default.dup)
                 end

        Steep.logger.tagged "target=#{name}" do
          target.instance_eval(&block) if block_given?
        end

        source_pattern = Pattern.new(patterns: target.sources, ignores: target.ignored_sources, ext: ".rb")
        signature_pattern = Pattern.new(patterns: target.signatures, ext: ".rbs")

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
          end,
          code_diagnostics_config: target.code_diagnostics_config
        ).tap do |target|
          project.targets << target
        end
      end
    end
  end
end
