module Steep
  class Project
    class Target
      attr_reader :name
      attr_reader :target_options

      attr_reader :source_pattern
      attr_reader :signature_pattern
      attr_reader :code_diagnostics_config
      attr_reader :project
      attr_reader :unreferenced
      attr_reader :groups
      attr_reader :implicitly_returns_nil

      def initialize(name:, options:, source_pattern:, signature_pattern:, code_diagnostics_config:, project:, unreferenced:, implicitly_returns_nil:)
        @name = name
        @target_options = options
        @source_pattern = source_pattern
        @signature_pattern = signature_pattern
        @code_diagnostics_config = code_diagnostics_config
        @project = project
        @unreferenced = unreferenced
        @groups = []
        @implicitly_returns_nil = implicitly_returns_nil
      end

      def options
        target_options || project.global_options
      end

      def possible_source_file?(path)
        if target = groups.find { _1.possible_source_file?(path) }
          return target
        end

        if source_pattern =~ path
          return self
        end

        nil
      end

      def possible_signature_file?(path)
        if target = groups.find { _1.possible_signature_file?(path) }
          return target
        end

        if signature_pattern =~ path
          return self
        end

        nil
      end

      def new_env_loader()
        Target.construct_env_loader(options: options, project: project)
      end

      def self.construct_env_loader(options:, project:)
        repo = RBS::Repository.new(no_stdlib: options.paths.customized_stdlib?)

        if options.paths.stdlib_root
          repo.add(project.absolute_path(options.paths.stdlib_root))
        end

        options.paths.repo_paths.each do |path|
          repo.add(project.absolute_path(path))
        end

        core_root_path =
          if options.paths.customized_core?
            if options.paths.core_root
              project.absolute_path(options.paths.core_root)
            end
          else
            RBS::EnvironmentLoader::DEFAULT_CORE_ROOT
          end

        loader = RBS::EnvironmentLoader.new(core_root: core_root_path, repository: repo)

        options.libraries.each do |lib|
          name, version = lib.split(/:/, 2)
          name or raise
          loader.add(library: name, version: version)
        end
        loader.add_collection(options.collection_lock) if options.collection_lock

        loader
      end
    end
  end
end
