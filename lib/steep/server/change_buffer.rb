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
                base64_decoded = content[:text].unpack1("m") #: String
                content = base64_decoded.force_encoding(Encoding::UTF_8)
              end
              changes[Pathname(filename.to_s)] = [Services::ContentChange.new(text: content)]
            end
          end
        end
      end
    end
  end
end
