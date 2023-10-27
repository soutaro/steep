module Steep
  module PathHelper
    module_function

    def to_pathname(uri, dosish: Gem.win_platform?)
      uri = URI.parse(uri)
      if uri.scheme == "file"
        path = uri.path or raise
        path.sub!(%r{^/([a-zA-Z])(:|%3A)//?}i, '\1:/') if dosish
        path = URI::DEFAULT_PARSER.unescape(path)
        Pathname(path)
      end
    end

    def to_pathname!(uri, dosish: Gem.win_platform?)
      to_pathname(uri, dosish: dosish) or raise "Cannot translate a URI to pathname: #{uri}"
    end

    def to_uri(path, dosish: Gem.win_platform?)
      str_path = path.to_s
      if dosish
        str_path.insert(0, "/") if str_path[0] != "/"
      end
      str_path = URI::DEFAULT_PARSER.escape(str_path)
      URI::File.build(path: str_path)
    end
  end
end
