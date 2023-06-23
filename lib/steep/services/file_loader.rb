module Steep
  module Services
    class FileLoader
      attr_reader :base_dir

      def initialize(base_dir:)
        @base_dir = base_dir
      end

      def each_path_in_patterns(pattern, commandline_patterns = [])
        if block_given?
          pats = commandline_patterns.empty? ? pattern.patterns : commandline_patterns

          pats.each do |path|
            absolute_path = base_dir + path

            if absolute_path.file?
              if pattern =~ path
                yield absolute_path.relative_path_from(base_dir)
              end
            else
              files = if absolute_path.directory?
                        Pathname.glob("#{absolute_path}/**/*#{pattern.ext}")
                      else
                        Pathname.glob(absolute_path.to_s)
                      end

              files.sort.each do |source_path|
                if source_path.file?
                  relative_path = source_path.relative_path_from(base_dir)
                  unless pattern.ignore?(relative_path)
                    yield relative_path
                  end
                end
              end
            end

          end
        else
          enum_for :each_path_in_patterns, pattern, commandline_patterns
        end
      end

      def load_changes(pattern, command_line_patterns = [], changes:)
        each_path_in_patterns(pattern, command_line_patterns) do |path|
          unless changes.key?(path)
            changes[path] = [ContentChange.string((base_dir + path).read)]
          end
        end

        changes
      end
    end
  end
end
