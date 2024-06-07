require "rake"
require "rake/tasklib"
require "steep/cli"

module Steep
  # Provides Rake tasks for running Steep commands.
  #
  # require "steep/rake_task"
  # Steep::RakeTask.new do |t|
  #   t.check.severity_level = :error
  #   t.watch.verbose
  #   t.stats << "--format=table"
  # end
  class RakeTask < Rake::TaskLib # steep:ignore UnknownConstant
    attr_accessor :name

    def self.available_commands
      %i(init check stats binstub project watch)
    end

    def initialize(name = :steep, cli_runner = default_cli_runner)
      super()

      @name = name

      configuration = TaskConfiguration.new

      yield configuration if block_given?

      define_tasks(configuration, cli_runner)
    end

    private

    # :nodoc:
    class TaskConfiguration
      def initialize
        @commands = {}
      end

      def method_missing(command)
        if respond_to?(command)
          @commands[command] ||= CommandConfiguration.new
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        RakeTask.available_commands.include?(name) || super
      end

      def options(command)
        @commands[command]&.to_a || []
      end
    end

    # :nodoc:
    class CommandConfiguration
      def initialize
        @options = []
      end

      def method_missing(name, value = nil)
        option = "--#{name.to_s.gsub(/_/, '-').gsub(/=/, '')}"
        option << "=#{value}" if value

        self << option
      end

      def respond_to_missing?(_name)
        true
      end

      def <<(value)
        @options << value
        self
      end

      def to_a
        @options
      end
    end

    def default_cli_runner
      lambda do |arguments|
        require "steep"

        cli = Steep::CLI.new(
          stdout: $stdout,
          stdin: $stdin,
          stderr: $stderr,
          argv: arguments
        )

        cli.run
      end
    end

    def define_tasks(configuration, cli_runner)
      namespace name do
        RakeTask.available_commands.each do |command|
          desc "Run steep #{command}"
          task command do |_, args|
            configured_options = configuration.options(command)

            argv = [
              command.to_s,
              *configured_options,
              *args.extras
            ]

            result = cli_runner[argv]

            raise "Steep failed" if result.nonzero?
          end
        end

        desc "Run steep help"
        task "help" do
          arguments = ["--help"]

          cli_runner[arguments]
        end
      end

      # Default steep task to steep:check
      desc "Run steep check" unless ::Rake.application.last_description # steep:ignore UnknownConstant
      task name => ["#{name}:check"]
    end
  end
end
