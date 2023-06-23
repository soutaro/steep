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

        loader = Services::FileLoader.new(base_dir: project.base_dir)

        project.targets.each do |target|
          source_changes = loader.load_changes(target.source_pattern, changes: {})
          signature_changes = loader.load_changes(target.signature_pattern, changes: {})

          stdout.puts "Target:"
          stdout.puts "  #{target.name}:"
          stdout.puts "    sources:"
          stdout.puts "      patterns:"
          target.source_pattern.patterns.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      ignores:"
          target.source_pattern.ignores.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      files:"
          source_changes.each_key do |path|
            stdout.puts "        - #{path}"
          end
          stdout.puts "    signatures:"
          stdout.puts "      patterns:"
          target.signature_pattern.patterns.each do |pattern|
            stdout.puts "        - #{pattern}"
          end
          stdout.puts "      files:"
          signature_changes.each_key do |path|
            stdout.puts "        - #{path}"
          end
          stdout.puts "    libraries:"
          target.options.libraries.each do |lib|
            stdout.puts "      - #{lib}"
          end
          stdout.puts "    library dirs:"
          target.new_env_loader(project: project).tap do |loader|
            loader.each_dir do |lib, path|
              case lib
              when :core
                stdout.puts "      - core: #{path}"
              when Pathname
                raise "Unexpected pathname from loader: path=#{path}"
              else
                stdout.puts "      - #{lib.name}(#{lib.version}): #{path}"
              end
            end
          end
        end

        0
      end
    end
  end
end
