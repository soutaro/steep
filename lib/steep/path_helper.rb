module Steep
  module PathHelper
    module_function

    def to_pathname(uri)
      path = URI.parse(uri).path
      path.sub!(%r{^/([a-zA-Z])(:|%3A)//?}i, '\1:/') if Gem.win_platform?
      Pathname(path)
    end

    def to_uri(path)
      str_path = path.to_s
      if Gem.win_platform?
        str_path.insert(0, "/") if str_path[0] != "/"
      end
      URI.parse(str_path).tap {|uri| uri.scheme = "file"}
    end
  end
end