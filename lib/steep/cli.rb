require 'optparse'

module Steep
  class CLI
    BUILTIN_PATH = Pathname(__dir__).join("../../stdlib").realpath

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
      [:init, :check, :validate, :annotations, :scaffold, :interface, :version, :project, :watch, :langserver]
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
      opts.on("--log-level=[debug,info,warn,error,fatal]") do |level|
        Steep.logger.level = level
      end

      opts.on("--log-output=[PATH]") do |file|
        Steep.log_output = file
      end

      opts.on("--verbose") do
        Steep.logger.level = Logger::DEBUG
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

    def process_init
      Drivers::Init.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep init [options]"

          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          opts.on("--force") { command.force_write = true }
          
          handle_logging_options opts
        end.parse!(argv)
      end.run()
    end

    def process_check
      Drivers::Check.new(stdout: stdout, stderr: stderr).tap do |check|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep check [options] [sources]"

          opts.on("--steepfile=PATH") {|path| check.steepfile = Pathname(path) }
          opts.on("--dump-all-types") { check.dump_all_types = true }
          handle_logging_options opts
        end.parse!(argv)

        check.command_line_patterns.push *argv
      end.run
    end

    def process_validate
      Drivers::Validate.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          handle_logging_options opts
        end.parse!(argv)
      end.run
    end

    def process_annotations
      Drivers::Annotations.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep annotations [options] [sources]"
          handle_logging_options opts
        end.parse!(argv)

        command.command_line_patterns.push *argv
      end.run
    end

    def process_scaffold
      OptionParser.new do |opts|
        opts.banner = "Usage: steep scaffold [options] [scripts]"
        handle_logging_options opts
      end.parse!(argv)

      source_paths = argv.map {|file| Pathname(file) }
      Drivers::Scaffold.new(source_paths: source_paths, stdout: stdout, stderr: stderr).run
    end

    def process_interface
      Drivers::PrintInterface.new(type_name: argv.first, stdout: stdout, stderr: stderr).tap do |command|
        opts.banner = "Usage: steep interface [options] [class_name]"
        OptionParser.new do |opts|
          handle_logging_options opts
        end.parse!(argv)
      end.run
    end

    def process_project
      Drivers::PrintProject.new(stdout: stdout, stderr: stderr).tap do |command|
        opts.banner = "Usage: steep project [options]"
        OptionParser.new do |opts|
          handle_logging_options opts
        end.parse!(argv)
      end.run
    end

    def process_watch
      Drivers::Watch.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep watch [options] [dirs]"
          handle_logging_options opts
        end.parse!(argv)

        command.dirs.push *argv
      end.run
    end

    def process_langserver
      Drivers::Langserver.new(stdout: stdout, stderr: stderr, stdin: stdin).tap do |command|
        OptionParser.new do |opts|
          handle_logging_options opts
        end.parse!(argv)
      end.run
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
