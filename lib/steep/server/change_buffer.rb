module Steep
  module Server
    module ChangeBuffer
      attr_reader :mutex
      attr_reader :buffered_changes

      def push_buffer
        mutex.synchronize do
          yield buffered_changes
        end
      end

      def pop_buffer
        changes = mutex.synchronize do
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

      def load_files(input)
        Steep.logger.tagged "#load_files" do
          push_buffer do |changes|
            input.each do |filename, content|
              if content.is_a?(Hash)
                content = Base64.decode64(content[:text]).force_encoding(Encoding::UTF_8)
              end
              changes[Pathname(filename.to_s)] = [Services::ContentChange.new(text: content)]
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
              changes.fetch(path) << Services::ContentChange.new(
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
