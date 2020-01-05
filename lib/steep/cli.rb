require 'optparse'

module Steep
  class CLI
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
      [:init, :check, :validate, :annotations, :version, :project, :watch, :langserver, :vendor]
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

    def process_vendor
      Drivers::Vendor.new(stdout: stdout, stderr: stderr, stdin: stdin).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep vendor [options] [dir]"
          handle_logging_options opts

          opts.on("--[no-]clean") do |v|
            command.clean_before = v
          end
        end.parse!(argv)

        command.vendor_dir = Pathname(argv[0] || "vendor/sigs")
      end.run
    end

    def process_version
      stdout.puts Steep::VERSION
      0
    end
  end
end
