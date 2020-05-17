module Steep
  module Server
    class SignatureWorker < BaseWorker
      attr_reader :queue
      attr_reader :last_target_validated_at

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)

        @queue = queue
        @last_target_validated_at = {}
      end

      def validate_signature_if_required(request)
        path = source_path(URI.parse(request[:params][:textDocument][:uri]))

        project.targets.each do |target|
          if target.signature_file?(path)
            enqueue_target target: target, timestamp: Time.now
          end
        end
      end

      def enqueue_target(target:, timestamp:)
        Steep.logger.debug "queueing target #{target.name}@#{timestamp}"
        last_target_validated_at[target] = timestamp
        queue << [target, timestamp]
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          # Don't respond to initialize request, but start type checking.
          project.targets.each do |target|
            enqueue_target(target: target, timestamp: Time.now)
          end
        when "textDocument/didChange"
          update_source(request)
          validate_signature_if_required(request)
        end
      end

      def validate_signature(target, timestamp:)
        Steep.logger.info "Starting signature validation: #{target.name} (#{timestamp})..."

        target.type_check(target_sources: [], validate_signatures: true)

        Steep.logger.info "Finished signature validation: #{target.name} (#{timestamp})"

        diagnostics = case status = target.status
                      when Project::Target::SignatureSyntaxErrorStatus
                        target.signature_files.each.with_object({}) do |(path, file), hash|
                          if file.status.is_a?(Project::SignatureFile::ParseErrorStatus)
                            location = case error = file.status.error
                                       when RBS::Parser::SyntaxError
                                         if error.error_value.is_a?(String)
                                           buf = RBS::Buffer.new(name: path, content: file.content)
                                           RBS::Location.new(buffer: buf, start_pos: buf.content.size, end_pos: buf.content.size)
                                         else
                                           error.error_value.location
                                         end
                                       when RBS::Parser::SemanticsError
                                         error.location
                                       else
                                         raise
                                       end

                            hash[path] =
                              [
                                LSP::Interface::Diagnostic.new(
                                  message: file.status.error.message,
                                  severity: LSP::Constant::DiagnosticSeverity::ERROR,
                                  range: LSP::Interface::Range.new(
                                    start: LSP::Interface::Position.new(
                                      line: location.start_line,
                                      character: location.start_column,
                                    ),
                                    end: LSP::Interface::Position.new(
                                      line: location.end_line,
                                      character: location.end_column
                                    )
                                  )
                                )
                              ]
                          else
                            hash[path] = []
                          end
                        end
                      when Project::Target::SignatureValidationErrorStatus
                        error_hash = status.errors.group_by {|error| error.location.buffer.name }

                        target.signature_files.each_key.with_object({}) do |path, hash|
                          errors = error_hash[path] || []
                          hash[path] = errors.map do |error|
                            LSP::Interface::Diagnostic.new(
                              message: StringIO.new.tap {|io| error.puts(io) }.string.split(/\t/, 2).last,
                              severity: LSP::Constant::DiagnosticSeverity::ERROR,
                              range: LSP::Interface::Range.new(
                                start: LSP::Interface::Position.new(
                                  line: error.location.start_line,
                                  character: error.location.start_column,
                                  ),
                                end: LSP::Interface::Position.new(
                                  line: error.location.end_line,
                                  character: error.location.end_column
                                )
                              )
                            )
                          end
                        end
                      when Project::Target::TypeCheckStatus
                        target.signature_files.each_key.with_object({}) do |path, hash|
                          hash[path] = []
                        end
                      else
                        Steep.logger.info "Unexpected target status: #{status.class}"
                      end

        diagnostics.each do |path, diags|
          writer.write(
            method: :"textDocument/publishDiagnostics",
            params: LSP::Interface::PublishDiagnosticsParams.new(
              uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
              diagnostics: diags
            )
          )
        end
      end

      def active_job?(target, timestamp)
        if last_target_validated_at[target] == timestamp
          sleep 0.1
          last_target_validated_at[target] == timestamp
        end
      end

      def handle_job(job)
        target, timestamp = job

        if active_job?(target, timestamp)
          validate_signature(target, timestamp: timestamp)
        else
          Steep.logger.info "Skipping signature validation: #{target.name}, queued timestamp=#{timestamp}, latest timestamp=#{last_target_validated_at[target]}"
        end
      end
    end
  end
end
