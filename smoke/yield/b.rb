class Foo
  # @type method bar: () ?{ (Integer) -> void } -> void
  def bar
    yield ""
  end
end
