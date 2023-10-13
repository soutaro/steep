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
      [:init, :check, :validate, :annotations, :version, :project, :watch, :langserver, :stats, :binstub, :checkfile]
    end

    def process_global_options
      OptionParser.new do |opts|
        opts.banner = <<~USAGE
          Usage: steep [options]

          available commands: #{CLI.available_commands.join(', ')}

          Options:
        USAGE

        opts.on("--version") do
          process_version
          exit 0
        end

        handle_logging_options(opts)
      end.order!(argv)

      true
    end

    def setup_command
      return false unless command = argv.shift&.to_sym
      @command = command

      if CLI.available_commands.include?(@command) || @command == :worker || @command == :vendor
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
      opts.on("--log-level=LEVEL", "Specify log level: debug, info, warn, error, fatal") do |level|
        Steep.logger.level = level
      end

      opts.on("--log-output=PATH", "Print logs to given path") do |file|
        Steep.log_output = file
      end

      opts.on("--verbose", "Set log level to debug") do
        Steep.logger.level = Logger::DEBUG
      end
    end

    def handle_jobs_option(option, opts)
      opts.on("-j N", "--jobs=N", "Specify the number of type check workers (defaults: #{option.default_jobs_count})") do |count|
        option.jobs_count = Integer(count) if Integer(count) > 0
      end

      opts.on("--steep-command=COMMAND", "Specify command to exec Steep CLI for worker (defaults: steep)") do |cmd|
        option.steep_command = cmd
      end
    end

    def setup_jobs_for_ci(jobs_option)
      if ENV["CI"]
        unless jobs_option.jobs_count
          stderr.puts Rainbow("CI environment is detected but no `--jobs` option is given.").yellow
          stderr.puts "  Using `[2, #{jobs_option.default_jobs_count} (# or processors)].min` to avoid hitting memory limit."
          stderr.puts "  Specify `--jobs` option to increase the number of jobs."

          jobs_option.jobs_count = [2, jobs_option.default_jobs_count].min
        end
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
      Drivers::Check.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep check [options] [sources]"

          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          opts.on("--with-expectations[=PATH]", "Type check with expectations saved in PATH (or steep_expectations.yml)") do |path|
            command.with_expectations_path = Pathname(path || "steep_expectations.yml")
          end
          opts.on("--save-expectations[=PATH]", "Save expectations with current type check result to PATH (or steep_expectations.yml)") do |path|
            command.save_expectations_path = Pathname(path || "steep_expectations.yml")
          end
          opts.on("--severity-level=LEVEL", /^error|warning|information|hint$/, "Specify the minimum diagnostic severity to be recognized as an error (defaults: warning): error, warning, information, or hint") do |level|
            command.severity_level = level.to_sym
          end
          handle_jobs_option command.jobs_option, opts
          handle_logging_options opts
        end.parse!(argv)

        setup_jobs_for_ci(command.jobs_option)
        
        command.command_line_patterns.push *argv
      end.run
    end

    def process_checkfile
      Drivers::Checkfile.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep checkfile [options] [files]"

          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          opts.on("--all-rbs", "Type check all RBS files") { command.all_rbs = true }
          opts.on("--all-ruby", "Type check all Ruby files") { command.all_ruby = true }
          opts.on("--stdin", "Read files to type check from stdin") do
            while line = stdin.gets()
              object = JSON.parse(line, symbolize_names: true)
              Steep.logger.info { "Loading content of `#{object[:path]}` from stdin: #{object[:content].lines[0].chomp}" }
              command.stdin_input[Pathname(object[:path])] = object[:content]
            end
          end
          handle_jobs_option command.jobs_option, opts
          handle_logging_options opts
        end.parse!(argv)

        setup_jobs_for_ci(command.jobs_option)

        command.command_line_args.push *argv
      end.run
    end

    def process_stats
      Drivers::Stats.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep stats [options] [sources]"

          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          opts.on("--format=FORMAT", "Specify output format: csv, table") {|format| command.format = format }
          handle_jobs_option command.jobs_option, opts
          handle_logging_options opts
        end.parse!(argv)

        setup_jobs_for_ci(command.jobs_option)

        command.command_line_patterns.push *argv
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
        OptionParser.new do |opts|
          opts.banner = "Usage: steep project [options]"
          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          handle_logging_options opts
        end.parse!(argv)
      end.run
    end

    def process_watch
      Drivers::Watch.new(stdout: stdout, stderr: stderr).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep watch [options] [dirs]"
          opts.on("--severity-level=LEVEL", /^error|warning|information|hint$/, "Specify the minimum diagnostic severity to be recognized as an error (defaults: warning): error, warning, information, or hint") do |level|
            # @type var level: String
            command.severity_level = _ = level.to_sym
          end
          handle_jobs_option command.jobs_option, opts
          handle_logging_options opts
        end.parse!(argv)

        setup_jobs_for_ci(command.jobs_option)

        dirs = argv.map {|dir| Pathname(dir) }
        command.dirs.push(*dirs)
      end.run
    end

    def process_langserver
      Drivers::Langserver.new(stdout: stdout, stderr: stderr, stdin: stdin).tap do |command|
        OptionParser.new do |opts|
          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          handle_jobs_option command.jobs_option, opts
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

    def process_binstub
      path = Pathname("bin/steep")
      root_path = Pathname.pwd
      force = false

      OptionParser.new do |opts|
        opts.banner = <<BANNER
Usage: steep binstub [options]

Generate a binstub to execute Steep with setting up Bundler and rbenv/rvm.
Use the executable for LSP integration setup.

Options:
BANNER
        handle_logging_options opts

        opts.on("-o PATH", "--output=PATH", "The path of the executable file (defaults to `bin/steep`)") do |v|
          path = Pathname(v)
        end

        opts.on("--root=PATH", "The repository root path (defaults to `.`)") do |v|
          root_path = (Pathname.pwd + v).cleanpath
        end

        opts.on("--[no-]force", "Overwrite file (defaults to false)") do
          force = true
        end
      end.parse!(argv)

      binstub_path = (Pathname.pwd + path).cleanpath
      bindir_path = binstub_path.parent

      bindir_path.mkpath

      gemfile_path =
        if defined?(Bundler)
          Bundler.default_gemfile.relative_path_from(bindir_path)
        else
          Pathname("../Gemfile")
        end

      if binstub_path.file?
        if force
          stdout.puts Rainbow("#{path} already exists. Overwriting...").yellow
        else
          stdout.puts Rainbow(''"⚠️ #{path} already exists. Bye! 👋").red
          return 0
        end
      end

      template = <<TEMPLATE
#!/usr/bin/env bash

BINSTUB_DIR=$(cd $(dirname $0); pwd)
GEMFILE=$(readlink -f ${BINSTUB_DIR}/#{gemfile_path})
ROOT_DIR=$(readlink -f ${BINSTUB_DIR}/#{root_path.relative_path_from(bindir_path)})

STEEP="bundle exec --gemfile=${GEMFILE} steep"

if type "rbenv" > /dev/null 2>&1; then
  STEEP="rbenv exec ${STEEP}"
else
  if type "rvm" > /dev/null 2>&1; then
    if [ -e ${ROOT_DIR}/.ruby-version ]; then
      STEEP="rvm ${ROOT_DIR} do ${STEEP}"
    fi
  fi
fi

exec $STEEP $@
TEMPLATE

      binstub_path.write(template)
      binstub_path.chmod(0755)

      stdout.puts Rainbow("Successfully generated executable #{path} 🎉").blue

      0
    end

    def process_version
      stdout.puts Steep::VERSION
      0
    end

    def process_worker
      Drivers::Worker.new(stdout: stdout, stderr: stderr, stdin: stdin).tap do |command|
        OptionParser.new do |opts|
          opts.banner = "Usage: steep worker [options] [dir]"
          handle_logging_options opts

          opts.on("--interaction") { command.worker_type = :interaction }
          opts.on("--typecheck") { command.worker_type = :typecheck }
          opts.on("--steepfile=PATH") {|path| command.steepfile = Pathname(path) }
          opts.on("--name=NAME") {|name| command.worker_name = name }
          opts.on("--delay-shutdown") { command.delay_shutdown = true }
          opts.on("--max-index=COUNT") {|count| command.max_index = Integer(count) }
          opts.on("--index=INDEX") {|index| command.index = Integer(index) }
        end.parse!(argv)

        command.commandline_args.push(*argv)
      end.run
    end
  end
end
