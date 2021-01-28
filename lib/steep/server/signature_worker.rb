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
        queue << [:validate, [target, timestamp]]
      end

      def enqueue_symbol(id:, query:)
        Steep.logger.debug "queueing symbol #{query} (#{id})"
        queue << [:symbol, [id, query]]
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          # Start type checking.
          project.targets.each do |target|
            enqueue_target(target: target, timestamp: Time.now)
          end

          writer.write({ id: request[:id], result: nil})

        when "textDocument/didChange"
          update_source(request)
          validate_signature_if_required(request)
        when "workspace/symbol"
          enqueue_symbol(query: request[:params][:query], id: request[:id])
        end
      end

      def validate_signature(target, timestamp:)
        Steep.logger.info "Starting signature validation: #{target.name} (#{timestamp})..."

        target.type_check(target_sources: [], validate_signatures: true)

        Steep.logger.info "Finished signature validation: #{target.name} (#{timestamp})"

        diagnostics = case status = target.status
                      when Project::Target::SignatureErrorStatus
                        error_hash = status.errors.group_by {|error| error.location.buffer.name }
                        formatter = Diagnostic::LSPFormatter.new

                        target.signature_files.each_key.with_object({}) do |path, hash|
                          errors = error_hash[path] || []
                          hash[path] = errors.map {|error| formatter.format(error) }
                        end
                      when Project::Target::TypeCheckStatus
                        target.signature_files.each_key.with_object({}) do |path, hash|
                          hash[path] = []
                        end
                      else
                        Steep.logger.info "Unexpected target status: #{status.class}"
                        {}
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

      def handle_workspace_symbol(query:, id:)
        provider = Index::SignatureSymbolProvider.new()

        project.targets.each do |target|
          case target.status
          when Project::Target::TypeCheckStatus
            index = Index::RBSIndex.new()

            builder = Index::RBSIndex::Builder.new(index: index)
            builder.env(target.status.environment)

            provider.indexes << index
          end
        end

        symbols = provider.query_symbol(query)

        result = symbols.map do |symbol|
          {
            name: symbol.name.to_s,
            kind: symbol.kind,
            deprecated: false,
            containerName: symbol.container_name.to_s,
            location: {
              uri: URI.parse(project.absolute_path(symbol.location.buffer.name).to_s),
              range: {
                start: LSP::Interface::Position.new(
                  line: symbol.location.start_line - 1,
                  character: symbol.location.start_column,
                  ),
                end: LSP::Interface::Position.new(
                  line: symbol.location.end_line - 1,
                  character: symbol.location.end_column
                )
              }
            }
          }
        end

        writer.write(id: id, result: result)
      end

      def handle_job(job)
        action, data = job

        case action
        when :validate
          target, timestamp = data

          if active_job?(target, timestamp)
            validate_signature(target, timestamp: timestamp)
          else
            Steep.logger.info "Skipping signature validation: #{target.name}, queued timestamp=#{timestamp}, latest timestamp=#{last_target_validated_at[target]}"
          end
        when :symbol
          id, query = data
          handle_workspace_symbol(query: query, id: id)
        end
      end
    end
  end
end
