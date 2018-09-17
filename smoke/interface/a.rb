class A
  # @dynamic foo

  def hello
    # !expects NoMethodError: type=::A::Object, method=bar
    foo.foo.bar

    # @type var object: ::Object
    object = _ = nil

    # !expects NoMethodError: type=::Object, method=object?
    object.object?
  end
end
