require 'optparse'

module Steep
  class CLI
    BUILTIN_PATH = Pathname(__dir__).join("../../stdlib").realpath

    class SignatureOptions
      attr_reader :no_builtin
      attr_reader :no_bundler
      attr_reader :libraries
      attr_reader :paths

      def initialize
        @libraries = []
        @paths = []
      end

      def no_builtin!
        @no_builtin = true
      end

      def no_bundler!
        @no_bundler = true
      end

      def add(path: nil, library: nil)
        case
        when path
          paths << path
        when library
          libraries << library
        end
      end

      def signature_paths
        if paths.empty? && Pathname("sig").directory?
          [Pathname("sig")]
        else
          paths
        end
      end

      def setup(loader:)
        libraries.each do |lib|
          loader.add library: lib
        end

        signature_paths.each do |path|
          loader.add path: path
        end

        loader.stdlib_root = nil if no_builtin
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
      [:check, :validate, :annotations, :scaffold, :interface, :version, :paths, :watch, :langserver]
    end

    def process_global_options
      OptionParser.new do |opts|
        opts.on("--version") do
          process_version
          exit 0
        end

        handle_logging_options(opts)
      end.order!(argv)

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

    def handle_logging_options(opts)
      opts.on("--verbose") do
        Steep.logger.level = Logger::DEBUG
      end

      opts.on("--log-level=[debug,info,warn,error,fatal]") do |level|
        lv = {
          "debug" => Logger::DEBUG,
          "info" => Logger::INFO,
          "warn" => Logger::WARN,
          "error" => Logger::ERROR,
          "fatal" => Logger::FATAL
        }[level.downcase] or raise "Unknown error level: #{level}"

        Steep.logger.level = lv
      end

      opts.on("--log-output=[PATH]") do |file|
        Steep.log_output = file
      end
    end

    def handle_dir_options(opts, options)
      opts.on("-I [PATH]") {|path| options.add path: Pathname(path) }
      opts.on("-r [library]") {|lib| options.add(library: lib) }
      opts.on("--no-builtin") { options.no_builtin! }
      opts.on("--no-bundler") { options.no_bundler! }
    end

    def with_signature_options
      yield SignatureOptions.new
    rescue Ruby::Signature::EnvironmentLoader::UnknownLibraryNameError => exn
      stderr.puts "UnknownLibraryNameError: library=#{exn.name}"
      1
    end

    def process_check
      with_signature_options do |signature_options|
        dump_all_types = false
        fallback_any_is_error = false
        strict = false

        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
          opts.on("--dump-all-types") { dump_all_types = true }
          opts.on("--strict") { strict = true }
          opts.on("--fallback-any-is-error") { fallback_any_is_error = true }
        end.parse!(argv)

        source_paths = argv.map {|path| Pathname(path) }
        if source_paths.empty?
          source_paths << Pathname(".")
        end

        Drivers::Check.new(source_paths: source_paths, signature_options: signature_options, stdout: stdout, stderr: stderr).tap do |check|
          check.dump_all_types = dump_all_types
          check.fallback_any_is_error = fallback_any_is_error || strict
          check.allow_missing_definitions = false if strict
        end.run
      end
    end

    def process_validate
      with_signature_options do |signature_options|
        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
        end.parse!(argv)

        Drivers::Validate.new(signature_options: signature_options, stdout: stdout, stderr: stderr).run
      end
    end

    def process_annotations
      OptionParser.new do |opts|
        handle_logging_options opts
      end.parse!(argv)

      source_paths = argv.map {|file| Pathname(file) }
      Drivers::Annotations.new(source_paths: source_paths, stdout: stdout, stderr: stderr).run
    end

    def process_scaffold
      OptionParser.new do |opts|
        handle_logging_options opts
      end.parse!(argv)

      source_paths = argv.map {|file| Pathname(file) }
      Drivers::Scaffold.new(source_paths: source_paths, stdout: stdout, stderr: stderr).run
    end

    def process_interface
      with_signature_options do |signature_options|
        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
        end.parse!(argv)

        Drivers::PrintInterface.new(type_name: argv.first, signature_options: signature_options, stdout: stdout, stderr: stderr).run
      end
    end

    def process_watch
      with_signature_options do |signature_options|
        strict = false
        fallback_any_is_error = false

        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
          opts.on("--strict") { strict = true }
          opts.on("--fallback-any-is-error") { fallback_any_is_error = true }
        end.parse!(argv)

        source_dirs = argv.map {|path| Pathname(path) }
        if source_dirs.empty?
          source_dirs << Pathname(".")
        end

        Drivers::Watch.new(source_dirs: source_dirs, signature_dirs: signature_options.paths, stdout: stdout, stderr: stderr).tap do |driver|
          driver.options.fallback_any_is_error = fallback_any_is_error || strict
          driver.options.allow_missing_definitions = false if strict
        end.run

        0
      end
    end

    def process_langserver
      with_signature_options do |signature_options|
        strict = false
        fallback_any_is_error = false

        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
          opts.on("--strict") { strict = true }
          opts.on("--fallback-any-is-error") { fallback_any_is_error = true }
        end.parse!(argv)

        source_dirs = argv.map { |path| Pathname(path) }
        if source_dirs.empty?
          source_dirs << Pathname(".")
        end

        Drivers::Langserver.new(source_dirs: source_dirs, signature_options: signature_options).tap do |driver|
          driver.options.fallback_any_is_error = fallback_any_is_error || strict
          driver.options.allow_missing_definitions = false if strict
        end.run

        0
      end
    end

    def process_version
      stdout.puts Steep::VERSION
      0
    end

    def process_paths
      with_signature_options do |signature_options|
        OptionParser.new do |opts|
          handle_logging_options opts
          handle_dir_options opts, signature_options
        end.parse!(argv)

        loader = Ruby::Signature::EnvironmentLoader.new
        signature_options.setup loader: loader

        loader.paths.each do |path|
          case path
          when Pathname
            stdout.puts "#{path}"
          when Ruby::Signature::EnvironmentLoader::GemPath
            stdout.puts "#{path.path} (gem, name=#{path.name}, version=#{path.version})"
          when Ruby::Signature::EnvironmentLoader::LibraryPath
            stdout.puts "#{path.path} (library, name=#{path.name})"
          end
        end

        0
      end
    end
  end
end
