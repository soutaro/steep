require 'optparse'

module Steep
  class CLI
    BUILTIN_PATH = Pathname(__dir__).join("../../stdlib").realpath

    class SignatureOptions
      class MissingGemError < StandardError
        attr_reader :name
        attr_reader :version

        def initialize(name:, version:)
          @name = name
          @version = version
          super "Requested gem not found: name=#{name}, version=#{version}"
        end
      end

      class NoTypeDefinitionFromGemError < StandardError
        attr_reader :gemspec

        def initialize(gemspec:)
          @gemspec = gemspec
          super "Gem does not provide Steep type: gem=#{gemspec.name}"
        end
      end

      attr_reader :no_builtin
      attr_reader :no_bundler

      def initialize
        @options = []
      end

      def no_builtin!
        @no_builtin = true
      end

      def no_bundler!
        @no_bundler = true
      end

      def <<(option)
        @options << option
      end

      def find_gem_dir(gem)
        name, version = gem.split(/:/)
        spec =
          begin
            Gem::Specification.find_by_name(name, version)
          rescue Gem::MissingSpecError
            raise MissingGemError.new(name: name, version: version)
          end

        dirs_from_spec(spec).tap do |dirs|
          if dirs.empty?
            raise NoTypeDefinitionFromGemError.new(gemspec: spec)
          end
        end
      end

      def dirs_from_spec(spec)
        type_dirs = spec.metadata["steep_types"].yield_self do |types|
          case types
          when nil
            []
          when String
            types.split(/:/).map do |type|
              Pathname(type)
            end
          end
        end

        base_dir = Pathname(spec.gem_dir)
        type_dirs.map do |dir|
          base_dir + dir
        end.select(&:directory?)
      end

      def add_bundler_gems(options)
        if defined?(Bundler)
          Steep.logger.info "Bundler detected!"
          Bundler.load.gems.each do |spec|
            dirs = dirs_from_spec(spec)
            options.unshift *dirs
          end
        end
      end

      def library_paths
        options = @options.reject {|option| option.is_a?(Pathname) }

        paths = []

        unless no_bundler
          add_bundler_gems(paths)
        end

        options.each do |option|
          paths.push *find_gem_dir(option)
        end

        paths.reverse.uniq(&:realpath).reverse
      end

      def signature_paths
        @options.select {|option| option.is_a?(Pathname) }.yield_self do |paths|
          if paths.empty? && Pathname("sig").directory?
            [Pathname("sig")]
          else
            paths
          end
        end
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
      opts.on("-I [PATH]") {|path| options << Pathname(path) }
      opts.on("-G [GEM]") {|gem| options << gem }
      opts.on("--no-builtin") { options.no_builtin! }
      opts.on("--no-bundler") { options.no_bundler! }
    end

    def with_signature_options
      yield SignatureOptions.new
    rescue SignatureOptions::MissingGemError => exn
      stderr.puts Rainbow("Gem not found: name=#{exn.name}, version=#{exn.version}").red
      1
    rescue SignatureOptions::NoTypeDefinitionFromGemError => exn
      stderr.puts Rainbow("Type definition directory not found: #{exn.gemspec.name} (#{exn.gemspec.version})").red
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

        Drivers::Check.new(source_paths: source_paths, signature_dirs: signature_options.paths, stdout: stdout, stderr: stderr).tap do |check|
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

        stdout.puts "Signature paths:"
        signature_options.signature_paths.each do |path|
          stdout.puts "  #{path}"
        end

        stdout.puts "Library paths:"
        signature_options.library_paths.each do |path|
          stdout.puts "  #{path}"
        end

        0
      end
    end
  end
end
