module Steep
  module Drivers
    class PrintProject
      attr_reader :stdout
      attr_reader :stderr

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources([])
        loader.load_signatures()

        project.targets.each do |target|
          stdout.puts "Target:"
          stdout.puts "  #{target.name}:"
          stdout.puts "    sources:"
          stdout.puts "      patterns:"
          target.source_patterns.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      ignores:"
          target.ignore_patterns.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      files:"
          target.source_files.each_key do |path|
            stdout.puts "        - #{path}"
          end
          stdout.puts "    signatures:"
          stdout.puts "      patterns:"
          target.signature_patterns.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      files:"
          target.signature_files.each_key do |path|
            stdout.puts "        - #{path}"
          end
          stdout.puts "    libraries:"
          target.options.libraries.each do |lib|
            stdout.puts "      - #{lib}"
          end
        end

        0
      end
    end
  end
end
