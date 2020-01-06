module Steep
  class Project
    class FileLoader
      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def each_source_path(patterns, &block)
        patterns.each do |path|
          case
          when File.file?(path)
            yield Pathname(path)
          when File.directory?(path)
            Pathname.glob("#{path}/**/*.rb")
          else
            Pathname.glob(path).each(&block)
          end
        end
      end

      def load_sources(command_line_patterns)
        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            target_patterns = command_line_patterns.empty? ? target.source_patterns : command_line_patterns

            each_source_path target_patterns do |path|
              if target.possible_source_file?(path)
                unless target.source_file?(path)
                  Steep.logger.info { "Adding source file: #{path}" }
                  target.add_source path, path.read
                end
              end
            end
          end
        end
      end

      def each_signature_path(patterns, &block)
        patterns.each do |path|
          case
          when File.file?(path)
            yield Pathname(path)
          when File.directory?(path)
            Pathname.glob("#{path}/**/*.rbs").each(&block)
          else
            Pathname.glob(path).each(&block)
          end
        end
      end

      def load_signatures()
        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            each_signature_path target.signature_patterns do |path|
              if target.possible_signature_file?(path)
                unless target.signature_file?(path)
                  Steep.logger.info { "Adding signature file: #{path}" }
                  target.add_signature path, path.read
                end
              end
            end
          end
        end
      end
    end
  end
end
