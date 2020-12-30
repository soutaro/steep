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

  baz

  tap do
    baz
  end
end
