class B
  Request = _ = Struct.new(:method, :path, keyword_init: true) do
    # @implements Request

    def post?
      method == "POST"
    end

    def get?
      method == "GET"
    end
  end
end
