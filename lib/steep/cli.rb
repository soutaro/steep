require 'optparse'

module Steep
  class CLI
    BUILTIN_PATH = Pathname(__dir__).join("../../stdlib").realpath

    class SignatureOptions
      attr_reader :no_builtin

      def initialize
        @options = []
      end

      def no_builtin!
        @no_builtin = true
      end

      def <<(option)
        @options << option
      end

      def find_gem_dir(gem)
        name, version = gem.split(/:/)
        spec = Gem::Specification.find_by_name(name, version)

        type_dirs = spec.metadata["steep_types"].yield_self do |types|
          case types
          when nil
            []
          when true
            [Pathname("sig")]
          else
            Array(types).map do |type|
              Pathname(type)
            end
          end
        end

        base_dir = Pathname(spec.base_dir)
        type_dirs.map do |dir|
          base_dir + dir
        end.select(&:directory?)
      end

      def paths
        options = if @options.none? {|option| option.is_a?(Pathname) }
                    [Pathname("sig")]
                  else
                    @options
                  end

        paths = options.flat_map do |option|
          case option
          when Pathname
            # Dir
            [option]
          when String
            # gem name
            find_gem_dir(option)
          end
        end

        unless no_builtin
          paths.unshift BUILTIN_PATH
        end

        paths
      end
    end

    attr_reader :argv
    attr_reader :stdout
    attr_reader :stdin
    attr_reader :stderr
    attr_reader :command

    def initialize(stdout:, stdin:, stderr:, argv:)
      @stdout = stdout
      @stdin = stdin
      @stderr = stderr
      @argv = argv
    end

    def self.available_commands
      [:check, :validate, :annotations, :scaffold, :interface, :version, :paths]
    end

    def process_global_options
      OptionParser.new do |opts|
        opts.on("--version") do
          process_version
          exit 0
        end
      end.order!

      true
    end

    def setup_command
      @command = argv.shift&.to_sym
      if CLI.available_commands.include?(@command)
        true
      else
        stderr.puts "Unknown command: #{command}"
        stderr.puts "  available commands: #{CLI.available_commands.join(', ')}"
        false
      end
    end

    def run
      process_global_options or return 1
      setup_command or return 1

      __send__(:"process_#{command}")
    end

    def handle_dir_options(opts, options)
      opts.on("-I [PATH]") {|path| options << Pathname(path) }
      opts.on("-G [GEM]") {|gem| options << gem }
      opts.on("--no-builtin") { options.no_builtin! }
    end

    def process_check
      signature_options = SignatureOptions.new
      verbose = false
      dump_all_types = false
      fallback_any_is_error = false
      strict = false

      OptionParser.new do |opts|
        handle_dir_options opts, signature_options
        opts.on("--verbose") { verbose = true }
        opts.on("--dump-all-types") { dump_all_types = true }
        opts.on("--strict") { strict = true }
        opts.on("--fallback-any-is-error") { fallback_any_is_error = true }
      end.parse!(argv)

      source_paths = argv.map {|path| Pathname(path) }
      if source_paths.empty?
        source_paths << Pathname(".")
      end

      Drivers::Check.new(source_paths: source_paths, signature_dirs: signature_options.paths, stdout: stdout, stderr: stderr).tap do |check|
        check.verbose = verbose
        check.dump_all_types = dump_all_types
        check.fallback_any_is_error = fallback_any_is_error || strict
        check.allow_missing_definitions = false if strict
      end.run
    end

    def process_validate
      verbose = false
      signature_options = SignatureOptions.new

      OptionParser.new do |opts|
        handle_dir_options opts, signature_options
        opts.on("--verbose") { verbose = true }
      end.parse!(argv)

      Drivers::Validate.new(signature_dirs: signature_options.paths, stdout: stdout, stderr: stderr).tap do |validate|
        validate.verbose = verbose
      end.run
    end

    def process_annotations
      source_paths = argv.map {|file| Pathname(file) }
      Drivers::Annotations.new(source_paths: source_paths, stdout: stdout, stderr: stderr).run
    end

    def process_scaffold
      source_paths = argv.map {|file| Pathname(file) }
      Drivers::Scaffold.new(source_paths: source_paths, stdout: stdout, stderr: stderr).run
    end

    def process_interface
      signature_options = SignatureOptions.new

      OptionParser.new do |opts|
        handle_dir_options opts, signature_options
      end.parse!(argv)

      Drivers::PrintInterface.new(type_name: argv.first, signature_dirs: signature_options.paths, stdout: stdout, stderr: stderr).run
    end

    def process_version
      stdout.puts Steep::VERSION
    end

    def process_paths
      signature_options = SignatureOptions.new

      OptionParser.new do |opts|
        handle_dir_options opts, signature_options
      end.parse!(argv)

      signature_options.paths.each do |path|
        stdout.puts path
      end
    end
  end
end
