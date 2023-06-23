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

            project.targets.each do |target|
              if collection_lock = target.options.collection_lock
                begin
                  collection_lock.check_rbs_availability!
                rescue RBS::Collection::Config::CollectionNotAvailable
                  raise "Run `rbs collection install` to install type definitions"
                end
              end
            end
          end
        end

        def request_id
          SecureRandom.alphanumeric(10)
        end

        def wait_for_response_id(reader:, id:, unknown_responses: :ignore)
          wait_for_message(reader: reader, unknown_messages: unknown_responses) do |response|
            response[:id] == id
          end
        end

        def shutdown_exit(writer:, reader:)
          request_id().tap do |id|
            writer.write({ method: :shutdown, id: id })
            wait_for_response_id(reader: reader, id: id)
          end
          writer.write({ method: :exit })
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

        def keep_diagnostic?(diagnostic, severity_level:)
          severity = diagnostic[:severity]

          case severity_level
          when nil, :hint
            true
          when :error
            severity <= LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR
          when :warning
            severity <= LanguageServer::Protocol::Constant::DiagnosticSeverity::WARNING
          when :information
            severity <= LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION
          end
        end
      end
    end
  end
end
