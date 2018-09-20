interface _Each<'a, 'b>
  def each: { ('a) -> any } -> 'b
end

module A : _Each<Integer, A>
  def count: () -> Integer
end

module X
  def foo: () -> Integer
end

module Palette
  def self?.defacto_palette: -> Array<Array<Integer>>
  def self.nestopia_palette: -> Array<Array<Integer>>
end
