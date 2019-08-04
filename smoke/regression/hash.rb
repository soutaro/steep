class Foo
  # @type method foo: (Hash[String, any]) -> void
  def foo(x)
    # @type ivar @y: Hash[String, any]
    @y = x
  end
end
