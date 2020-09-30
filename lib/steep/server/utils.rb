module Steep
  module Server
    module Utils
      LSP = LanguageServer::Protocol

      def source_path(uri)
        project.relative_path(Pathname(uri.path))
      end

      def apply_change(change, text)
        range = change[:range]

        if range
          text = text.dup

          buf = AST::Buffer.new(name: :_, content: text)

          start_pos = buf.loc_to_pos(range[:start].yield_self {|pos| [pos[:line]+1, pos[:character]] })
          end_pos = buf.loc_to_pos(range[:end].yield_self {|pos| [pos[:line]+1, pos[:character]] })

          text[start_pos...end_pos] = change[:text]
          text
        else
          change[:text]
        end
      end

      def update_source(request)
        path = source_path(URI.parse(request[:params][:textDocument][:uri]))
        version = request[:params][:textDocument][:version]
        Steep.logger.info "Updateing source: path=#{path}, version=#{version}..."

        changes = request[:params][:contentChanges]
        changes.each do |change|
          project.targets.each do |target|
            case
            when target.source_file?(path)
              target.update_source(path) {|text| apply_change(change, text) }
            when target.possible_source_file?(path)
              target.add_source(path, change[:text])
            when target.signature_file?(path)
              target.update_signature(path) {|text| apply_change(change, text) }
            when target.possible_signature_file?(path)
              target.add_signature(path, change[:text])
            end
          end
        end

        if block_given?
          yield path, version
        end
      end
    end
  end
end
