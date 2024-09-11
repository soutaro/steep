module Steep
  module Drivers
    module Utils
      module DriverHelper
        attr_accessor :steepfile

        def load_config(path: steepfile || Pathname("Steepfile"))
          if path.file?
            steep_file_path = path.absolute? ? path : Pathname.pwd + path
            Project.new(steepfile_path: steep_file_path).tap do |project|
              Project::DSL.parse(project, path.read, filename: path.to_s)
            end
          else
            Steep.ui_logger.error { "Cannot find a configuration at #{path}: `steep init` to scaffold. Using current directory..." }
            Project.new(steepfile_path: nil, base_dir: Pathname.pwd).tap do |project|
              Project::DSL.new(project: project).target :'.' do
                check '.'
                signature '.'
              end
            end
          end.tap do |project|
            project.targets.each do |target|
              case result = target.options.load_collection_lock
              when nil, RBS::Collection::Config::Lockfile
                # ok
              else
                if result == target.options.collection_config_path
                  Steep.ui_logger.error { "rbs-collection setup is broken: `#{result}` is missing" }
                else
                  Steep.ui_logger.error { "Run `rbs collection install` to install type definitions" }
                end
              end
            end
          end
        end

        def request_id
          SecureRandom.alphanumeric(10)
        end

        def wait_for_response_id(reader:, id:, unknown_responses: nil, &block)
          reader.read do |message|
            Steep.logger.debug { "Received message waiting for #{id}: #{message.inspect}" }

            response_id = message[:id]

            if response_id == id
              return message
            end

            if block
              yield message
            else
              case unknown_responses
              when :ignore, nil
                # nop
              when :log
                Steep.logger.error { "Unexpected message: #{message.inspect}" }
              when :raise
                raise "Unexpected message: #{message.inspect}"
              end
            end
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

        (DEFAULT_CLI_LSP_INITIALIZE_PARAMS = {}).freeze
      end
    end
  end
end
