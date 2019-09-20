# frozen_string_literal: true

require "optparse"

module Steep
  class Configuration
    class << self
      # with_merged_options
      #
      # This method yields a new configuration object
      # with merged results in the following precedence:
      #
      # 1. Command line arguments
      # 2. Steepfile DSL arguments
      # 3. Default arguments
      def with_merged_options(argv)
        configuration = Configuration.new

        merge_steepfile(configuration) if File.exists?("Steepfile")
        merge_cli_arguments(argv, configuration)
        yield(configuration)
      end

      private

      # merge_steepfile
      #
      # Reads Steepfile and loads all the
      # DSL configuration. For each configuration
      # provided in the Steepfile, invoke the appropriate
      # Configuration setter.
      def merge_steepfile(configuration)
        dsl = Dsl.new
        dsl.evaluate_steepfile(File.read("Steepfile"))

        dsl.instance_variables.each do |ivar|
          dsl_config = dsl.instance_variable_get(ivar)
          accessor_name = ivar.to_s.delete("@")

          configuration.send("#{accessor_name}=", dsl_config) unless dsl_config.nil?
        end
      end

      # merge_cli_arguments
      #
      # This method merges CLI arguments into the
      # configuration object.
      def merge_cli_arguments(argv, configuration)
        OptionParser.new do |options|
          options.on("-I [PATH]") { |path| configuration.signatures = [path] }
        end.parse!(argv)
      end
    end

    attr_reader :signatures

    def initialize
      @signatures = [Pathname("sig")]
    end

    def signatures=(paths)
      paths.each do |path|
        @signatures << Pathname(path)
      end
    end
  end
end
