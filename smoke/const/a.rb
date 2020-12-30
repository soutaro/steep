# @type const A: Integer
# @type var x: String

x = A

x = B

module X
  # @type const A: Integer

  def foo
    # @type var x: String

    x = A

    x = B
  end
end


# @type const Foo::Bar::Baz: Integer

x = Foo::Bar::Baz

z = Foo
x = z::Bar::Baz
x = ::Foo::Bar::Baz
