class A
  # @implements X

  def foo(x)
    :foobar
  end
end

class B
  # @implements X

  # @type method foo: (::String | ::Integer) -> untyped
  def foo(x)
    3
  end
end

class C
  # @implements X

  # @type method foo: (Symbol) -> Symbol
  def foo(x)
    :foo
  end
end
