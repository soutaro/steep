class Foo
  # @type method foo: (Hash[String, untyped]) -> void
  def foo(x)
    # @type ivar @y: Hash[String, untyped]
    @y = x
  end
end
