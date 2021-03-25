module Steep
  class Project
    class Target
      attr_reader :name
      attr_reader :options

      attr_reader :source_pattern
      attr_reader :signature_pattern

      def initialize(name:, options:, source_pattern:, signature_pattern:)
        @name = name
        @options = options
        @source_pattern = source_pattern
        @signature_pattern = signature_pattern

        @source_files = {}
        @signature_files = {}
      end

      def possible_source_file?(path)
        source_pattern =~ path
      end

      def possible_signature_file?(path)
        signature_pattern =~ path
      end

      def new_env_loader(project:)
        Target.construct_env_loader(options: options, project: project)
      end

      def self.construct_env_loader(options:, project:)
        repo = RBS::Repository.new(no_stdlib: options.vendor_path)
        options.repository_paths.each do |path|
          repo.add(project.absolute_path(path))
        end

        loader = RBS::EnvironmentLoader.new(
          core_root: options.vendor_path ? nil : RBS::EnvironmentLoader::DEFAULT_CORE_ROOT,
          repository: repo
        )
        loader.add(path: options.vendor_path) if options.vendor_path
        options.libraries.each do |lib|
          name, version = lib.split(/:/, 2)
          loader.add(library: name, version: version)
        end

        loader
      end
    end
  end
end
