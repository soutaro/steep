class DifferentMethodParameterKind
  # @type method foo: (Integer, String) -> void
  def foo(a = 0, *b)
  end

  # @type method bar: (name: String, size: Integer) -> void
  def bar(name: "foo", **rest)
  end
end
