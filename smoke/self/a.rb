def foo
  # @type self: A

  self.bar()

  tap do
    # @type self: A

    bar
  end
end

def bar
  # @type self: Object

  # !expects NoMethodError: type=Object, method=baz
  baz

  tap do
    # !expects NoMethodError: type=Object, method=baz
    baz
  end
end
