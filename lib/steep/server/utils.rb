module Steep
  module Server
    module Utils
      LSP = LanguageServer::Protocol

      def source_path(uri)
        project.relative_path(Pathname(uri.path))
      end

      def update_source(request)
        path = source_path(URI.parse(request[:params][:textDocument][:uri]))
        text = request[:params][:contentChanges][0][:text]
        version = request[:params][:textDocument][:version]

        Steep.logger.debug "Updateing source: path=#{path}, version=#{version}, size=#{text.bytesize}"

        project.targets.each do |target|
          case
          when target.source_file?(path)
            target.update_source path, text
          when target.possible_source_file?(path)
            target.add_source path, text
          when target.signature_file?(path)
            target.update_signature path, text
          when target.possible_signature_file?(path)
            target.add_signature path, text
          end
        end

        if block_given?
          yield path, version
        end
      end
    end
  end
end
