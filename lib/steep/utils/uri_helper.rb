module Steep
  module Utils
    module URIHelper
      def decode_uri(path)
        path = path.delete_prefix("file://")
        URI.decode_www_form_component(URI.parse(path).to_s)
      end

      def encode_uri(path)
        path = path.to_s.split("/").map { |dir|
          URI.encode_www_form_component(dir)
        }.join("/")

        URI.parse(path).tap do |uri|
          uri.scheme = "file"
        end
      end
    end
  end
end
