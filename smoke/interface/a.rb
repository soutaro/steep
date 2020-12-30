class A
  # @dynamic foo

  def hello
    foo.foo.bar

    # @type var object: ::Object
    object = _ = nil

    object.object?
  end
end
