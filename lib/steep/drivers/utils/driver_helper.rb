module Steep
  module Drivers
    module Utils
      module DriverHelper
        attr_accessor :steepfile

        def load_config(path: steepfile || Pathname("Steepfile"))
          raise "Cannot find a configuration at #{path}: `steep init` to scaffold" unless path.file?

          steep_file_path = path.absolute? ? path : Pathname.pwd + path
          Project.new(steepfile_path: steep_file_path).tap do |project|
            Project::DSL.parse(project, path.read, filename: path.to_s)
          end
        end

        def type_check(project)
          project.targets.each do |target|
            Steep.logger.tagged "target=#{target.name}" do
              target.type_check
            end
          end
        end

        def request_id
          (Time.now.to_f * 1000).to_i
        end

        def wait_for_response_id(reader:, id:, unknown_responses: :ignore)
          wait_for_message(reader: reader, unknown_messages: unknown_responses) do |response|
            response[:id] == id
          end
        end

        def wait_for_message(reader:, unknown_messages: :ignore, &block)
          reader.read do |message|
            if yield(message)
              return message
            else
              case unknown_messages
              when :ignore
                # nop
              when :log
                Steep.logger.error { "Unexpected message: #{message.inspect}" }
              when :raise
                raise "Unexpected message: #{message.inspect}"
              end
            end
          end
        end
      end
    end
  end
end
