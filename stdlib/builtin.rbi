class BasicObject
end

class Object <: BasicObject
  def tap: { (instance) -> any } -> instance
  def to_s: -> String
end

class Module
end

class Class <: Module
end

module Kernel
end

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
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
end

class Float <: Numeric
end

class Range<'a>
end

class String
  def to_str: -> String
end
