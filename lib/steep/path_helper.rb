module Steep
  module PathHelper
    module_function

    def to_pathname(uri, dosish: Gem.win_platform?)
      uri = URI.parse(uri)
      if uri.scheme == "file"
        path = uri.path
        path.sub!(%r{^/([a-zA-Z])(:|%3A)//?}i, '\1:/') if dosish
        Pathname(path)
      end
    end

    def to_uri(path, dosish: Gem.win_platform?)
      str_path = path.to_s
      if dosish
        str_path.insert(0, "/") if str_path[0] != "/"
      end
      URI::File.build(path: str_path)
    end
  end
end
