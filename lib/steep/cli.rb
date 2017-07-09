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
      accept_implicit_any = false

      OptionParser.new do |opts|
        opts.on("-I [PATH]") do |path| signature_dirs << Pathname(path) end
        opts.on("--verbose") do verbose = true end
        opts.on("--accept-implicit-any") do accept_implicit_any = true end
      end.parse!(argv)

      if signature_dirs.empty?
        signature_dirs << Pathname("sig")
      end

      source_paths = argv.map {|path| Pathname(path) }
      if source_paths.empty?
        source_paths << Pathname(".")
      end

      Drivers::Check.new(source_paths: source_paths, signature_dirs: signature_dirs, stdout: stdout, stderr: stderr).tap do |check|
        check.verbose = verbose
        check.accept_implicit_any = accept_implicit_any
      end.run
    end
  end
end
