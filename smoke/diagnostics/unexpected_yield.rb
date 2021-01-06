class UnexpectedYield
  # @type method foo: () -> void
  def foo
    yield
  end
end
