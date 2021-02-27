module Steep
  class Project
    class FileLoader
      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def each_path_in_patterns(pattern, commandline_patterns = [])
        pats = commandline_patterns.empty? ? pattern.patterns : commandline_patterns

        pats.each do |path|
          absolute_path = project.base_dir + path

          if absolute_path.file?
            yield project.relative_path(absolute_path)
          else
            files = if absolute_path.directory?
                      Pathname.glob("#{absolute_path}/**/*#{pattern.ext}")
                    else
                      Pathname.glob(absolute_path)
                    end

            files.sort.each do |source_path|
              unless pattern.ignore?(source_path)
                yield project.relative_path(source_path)
              end
            end
          end
        end
      end

      def load_sources(command_line_patterns)
        loaded_paths = Set[]

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            each_path_in_patterns(target.source_pattern, command_line_patterns) do |path|
              if loaded_paths.include?(path)
                Steep.logger.warn { "Skipping #{target} while loading #{path}... (Already loaded to another target.)" }
              else
                Steep.logger.info { "Adding source file: #{path}" }
                target.add_source path, project.absolute_path(path).read
                loaded_paths << path
              end
            end
          end
        end
      end

      def load_signatures()
        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            each_path_in_patterns target.signature_pattern do |path|
              unless target.signature_file?(path)
                Steep.logger.info { "Adding signature file: #{path}" }
                target.add_signature path, project.absolute_path(path).read
              end
            end
          end
        end
      end
    end
  end
end
