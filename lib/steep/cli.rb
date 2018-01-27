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
      [:check, :validate]
    end

    def setup_global_options
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
      setup_global_options or return 1
      setup_command or return 1

      __send__(:"process_#{command}")
    end

    def process_check
      signature_dirs = []
      verbose = false
      no_builtin = false
      dump_all_types = false
      fallback_any_is_error = false

      OptionParser.new do |opts|
        opts.on("-I [PATH]") {|path| signature_dirs << Pathname(path) }
        opts.on("--no-builtin") { no_builtin = true }
        opts.on("--verbose") { verbose = true }
        opts.on("--dump-all-types") { dump_all_types = true }
        opts.on("--fallback-any-is-error") { fallback_any_is_error = true }
      end.parse!(argv)

      if signature_dirs.empty?
        signature_dirs << Pathname("sig")
      end

      unless no_builtin
        signature_dirs.unshift Pathname(__dir__).join("../../stdlib").realpath
      end

      source_paths = argv.map {|path| Pathname(path) }
      if source_paths.empty?
        source_paths << Pathname(".")
      end

      Drivers::Check.new(source_paths: source_paths, signature_dirs: signature_dirs, stdout: stdout, stderr: stderr).tap do |check|
        check.verbose = verbose
        check.dump_all_types = dump_all_types
        check.fallback_any_is_error = fallback_any_is_error
      end.run
    end

    def process_validate
      verbose = false

      OptionParser.new do |opts|
        opts.on("--verbose") { verbose = true }
      end.parse!(argv)

      signature_dirs = argv.map {|path| Pathname(path) }
      if signature_dirs.empty?
        signature_dirs << Pathname(".")
      end

      Drivers::Validate.new(signature_dirs: signature_dirs, stdout: stdout, stderr: stderr).tap do |validate|
        validate.verbose = verbose
      end.run
    end
  end
end
