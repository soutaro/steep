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
      [:check]
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

      OptionParser.new do |opts|
        opts.on("-I [PATH]") {|path| signature_dirs << Pathname(path) }
        opts.on("--no-builtin") { no_builtin = true }
        opts.on("--verbose") { verbose = true }
      end.parse!(argv)

      unless no_builtin
        signature_dirs.unshift Pathname(__dir__).join("../../stdlib").realpath
      end

      if signature_dirs.empty?
        signature_dirs << Pathname("sig")
      end

      source_paths = argv.map {|path| Pathname(path) }
      if source_paths.empty?
        source_paths << Pathname(".")
      end

      Drivers::Check.new(source_paths: source_paths, signature_dirs: signature_dirs, stdout: stdout, stderr: stderr).tap do |check|
        check.verbose = verbose
      end.run
    end
  end
end
