class BasicObject
end

class Object <: BasicObject
  def tap: { (instance) -> any } -> instance
  def to_s: -> String
  def hash: -> Integer
  def eql?: (any) -> _Boolean
  def ==: (any) -> _Boolean
  def ===: (any) -> _Boolean
  def class: -> class
end

class Module
  def attr_reader: (*any) -> any
end

class Class<'instance> <: Module
  def new: -> 'instance
end

module Kernel
end

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
  def empty?: -> _Boolean
  def size: -> Integer
  def map: <'b> { ('a) -> 'b } -> Array<'b>
  def join: (any) -> String
  def all?: { (any) -> any } -> _Boolean
end

class Hash<'key, 'value>
end

class Symbol
end

interface _Boolean
end

class NilClass
end

class Numeric
end

class Integer <: Numeric
  def to_int: -> Integer
  def +: (Numeric) -> Integer
  def ^: (Numeric) -> Integer
end

class Float <: Numeric
end

class Range<'a>
end

class String
  def +: (String) -> String
  def to_str: -> String
  def size: -> Integer
end
