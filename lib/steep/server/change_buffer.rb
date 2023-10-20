module Steep
  module Server
    module ChangeBuffer
      attr_reader :mutex
      attr_reader :buffered_changes

      def push_buffer
        @mutex.synchronize do
          yield buffered_changes
        end
      end

      def pop_buffer
        changes = @mutex.synchronize do
          copy = buffered_changes.dup
          buffered_changes.clear
          copy
        end

        if block_given?
          yield changes
        else
          changes
        end
      end

      def load_files(project:, commandline_args:)
        Steep.logger.tagged "#load_files" do
          push_buffer do |changes|
            loader = Services::FileLoader.new(base_dir: project.base_dir)

            Steep.measure "load changes from disk" do
              project.targets.each do |target|
                loader.load_changes(target.source_pattern, commandline_args, changes: changes)
                loader.load_changes(target.signature_pattern, changes: changes)
              end
            end
          end
        end
      end

      def collect_changes(request)
        push_buffer do |changes|
          if path = Steep::PathHelper.to_pathname(request[:params][:textDocument][:uri])
            path = project.relative_path(path)
            version = request[:params][:textDocument][:version]
            Steep.logger.info { "Updating source: path=#{path}, version=#{version}..." }

            changes[path] ||= []
            request[:params][:contentChanges].each do |change|
              changes[path] << Services::ContentChange.new(
                range: change[:range]&.yield_self {|range|
                  [
                    range[:start].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) },
                    range[:end].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) }
                  ]
                },
                text: change[:text]
              )
            end
          end
        end
      end

      def reset_change(uri:, text:)
        push_buffer do |changes|
          if path = Steep::PathHelper.to_pathname(uri)
            path = project.relative_path(path)
            changes[path] = [Services::ContentChange.new(text: text)]
          end
        end
      end
    end
  end
end
