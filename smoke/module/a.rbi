interface _Each<'a>
  def each: { ('a) -> any } -> instance
end

module A : _Each<Integer>
  def count: () -> Integer
end
