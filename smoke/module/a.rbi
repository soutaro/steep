interface _Each<'a>
  def each: { ('a) -> any } -> instance
end

module A : _Each<Integer>
  def count: () -> Integer
end

module X
  def foo: () -> Integer
end

module Palette
  def self?.defacto_palette: -> Array<Array<Integer>>
  def self.nestopia_palette: -> Array<Array<Integer>>
end
