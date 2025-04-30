module Steep
  module Services
    class FileLoader
      attr_reader :base_dir

      def initialize(base_dir:)
        @base_dir = base_dir
      end

      def each_path_in_target(target, command_line_patterns = [], &block)
        if block
          done = Set[] #: Set[Pathname]

          handler = -> (path) do
            unless done.include?(path)
              done << path
              yield path
            end
          end

          target.groups.each do |group|
            each_path_in_patterns(group.source_pattern, command_line_patterns, &handler)
            each_path_in_patterns(group.inline_source_pattern, command_line_patterns, &handler)
            each_path_in_patterns(group.signature_pattern, &handler)
          end

          each_path_in_patterns(target.source_pattern, command_line_patterns, &handler)
          each_path_in_patterns(target.inline_source_pattern, command_line_patterns, &handler)
          each_path_in_patterns(target.signature_pattern, &handler)
        else
          enum_for :each_path_in_target, target, command_line_patterns
        end
      end

      def each_path_in_patterns(pattern, commandline_patterns = [])
        if block_given?
          pats = commandline_patterns.empty? ? pattern.patterns : commandline_patterns

          pats.each do |path|
            Pathname(base_dir).glob(path.to_s).each do |absolute_path|
              if absolute_path.file?
                relative_path = absolute_path.relative_path_from(base_dir)
                if pattern =~ relative_path
                  yield relative_path
                end
              else
                files = Pathname(absolute_path).glob("**/*#{pattern.ext}")

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
