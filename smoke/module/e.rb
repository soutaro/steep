# If module has a @implements annotation, it wins

module X
  # @implements A

  def count
    3
  end

  def foo
    "3"
  end
end
