class BasicObject
  def __id__: -> Integer
end

class Object <: BasicObject
  include Kernel
  def tap: { (instance) -> any } -> instance
  def to_s: -> String
  def hash: -> Integer
  def eql?: (any) -> _Boolean
  def ==: (any) -> _Boolean
  def ===: (any) -> _Boolean
  def !=: (any) -> _Boolean
  def class: -> class
  def to_i: -> Integer
  def is_a?: (Module) -> _Boolean
  def inspect: -> String
end

class Module
  def attr_reader: (*any) -> any
  def class: -> Class<Module>
  def tap: { (Module) -> any } -> Module
end

class Class<'instance> <: Module
  def allocate: -> 'instance
  def tap: { (any) -> any } -> any
  def class: -> any
end

module Kernel
  def raise: () -> any
           | (String) -> any

  def block_given?: -> _Boolean
  def include: (Module) -> _Boolean
  def prepend: (Module) -> _Boolean
  def enum_for: (Symbol, *any) -> any
end

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
  def empty?: -> _Boolean
  def size: -> Integer
  def map: <'b> { ('a) -> 'b } -> Array<'b>
  def join: (any) -> String
  def all?: { (any) -> any } -> _Boolean
  def sort_by: { ('a) -> any } -> Array<'a>
  def zip: <'b> (Array<'b>) -> Array<any>
  def each: { ('a) -> any } -> instance
          | -> Enumerator<'a, instance>
  def select: { ('a) -> any } -> Array<'a>
  def <<: ('a) -> instance
  def filter: { ('a) -> any } -> Array<'a>
end

class Hash<'key, 'value>
  def []: ('key) -> 'value
  def []=: ('key, 'value) -> 'value
  def size: -> Integer
  def transform_values: <'a> { ('value) -> 'a } -> Hash<'key, 'a>
  def each_key: { ('key) -> any } -> instance
              | -> Enumerator<'a, instance>
  def self.[]: (Array<any>) -> Hash<'key, 'value>
end

class Symbol
end

interface _Boolean
end

class NilClass
end

class Numeric
  def +: (Numeric) -> Numeric
end

class Integer <: Numeric
  def to_int: -> Integer
  def +: (Numeric) -> Integer
       | (Numeric) -> Numeric
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

class Enumerator<'a, 'this>
  def with_object: <'b> ('b) { ('a, 'b) -> any } -> 'b
  def with_index: { ('a, Integer) -> any } -> 'this
end
