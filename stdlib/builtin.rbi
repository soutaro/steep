class BasicObject
  def __id__: -> Integer
end

class Object <: BasicObject
  include Kernel
  def tap: { (self) -> any } -> self
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
  def freeze: -> self
  def method: (Symbol) -> Method
  def yield_self: <'a>{ (self) -> 'a } -> 'a
  def dup: -> self
  def send: (Symbol, *any) -> any
end

class Module
  def attr_reader: (*any) -> any
  def class: -> any
  def module_function: (*Symbol) -> any
                     | -> any
  def extend: (Module) -> any
  def attr_accessor: (*Symbol) -> any
  def attr_writer: (*Symbol) -> any
end

class Method
end

class Class<'instance> <: Module
  def new: (*any, **any) -> 'instance
  def class: -> Class.class
  def allocate: -> any
end

module Kernel
  def raise: () -> any
           | (String) -> any
           | (*any) -> any

  def block_given?: -> _Boolean
  def include: (Module) -> _Boolean
  def prepend: (Module) -> _Boolean
  def enum_for: (Symbol, *any) -> any
  def require_relative: (*String) -> void
  def require: (*String) -> void
  def loop: { () -> void } -> void
  def puts: (*any) -> void
  def eval: (String, ?Integer, ?String) -> any
end

class Array<'a>
  def []: (Integer) -> 'a
        | (Integer, Integer) -> self
  def []=: (Integer, 'a) -> 'a
         | (Integer, Integer, self) -> self
  def empty?: -> _Boolean
  def size: -> Integer
  def map: <'b> { ('a) -> 'b } -> Array<'b>
  def join: (any) -> String
  def all?: { (any) -> any } -> _Boolean
  def sort_by: { ('a) -> any } -> Array<'a>
  def zip: <'b> (Array<'b>) -> Array<any>
  def each: { ('a) -> any } -> instance
          | -> Enumerator<'a>
  def select: { ('a) -> any } -> Array<'a>
  def <<: ('a) -> instance
  def filter: { ('a) -> any } -> Array<'a>
  def *: (Integer) -> self
  def max: -> 'a
  def min: -> 'a
  def -: (self) -> self
  def sort: -> self
          | { ('a, 'a) -> any } -> self
  def include?: ('a) -> any
  def flat_map: <'b> { ('a) -> Array<'b> } -> Array<'b>
  def pack: (String, ?buffer: String) -> String
  def reverse: -> self
  def +: (self) -> self
  def last: -> 'a
  def slice!: (Integer) -> self
            | (Integer, Integer) -> self
            | (Range<Integer>) -> self
  def first: -> 'a
  def replace: (self) -> self
  def transpose: -> self
  def fill: ('a) -> self
end

class Hash<'key, 'value>
  def []: ('key) -> 'value
  def []=: ('key, 'value) -> 'value
  def size: -> Integer
  def transform_values: <'a> { ('value) -> 'a } -> Hash<'key, 'a>
  def each_key: { ('key) -> any } -> instance
              | -> Enumerator<'a>
  def self.[]: (Array<any>) -> Hash<'key, 'value>
end

class Symbol
  def self.all_symbols: -> Array<Symbol>
end

interface _Boolean
  def !: -> _Boolean
end

class NilClass
end

class Numeric
  def +: (Numeric) -> Numeric
  def /: (Numeric) -> Numeric
  def <=: (any) -> any
  def >=: (any) -> any
  def < : (any) -> any
  def >: (any) -> any
end

class Integer <: Numeric
  def to_int: -> Integer
  def +: (Integer) -> Integer
       | (Numeric) -> Numeric
  def ^: (Numeric) -> Integer
  def *: (Integer) -> Integer
       | (Float) -> Float
       | (Numeric) -> Numeric
  def >>: (Integer) -> Integer
  def step: (Integer, ?Integer) { (Integer) -> any } -> self
          | (Integer, ?Integer) -> Enumerator<Integer>
  def times: { (Integer) -> any } -> self
  def %: (Integer) -> Integer
  def -: (Integer) -> Integer
       | (Float) -> Float
       | (Numeric) -> Numeric
  def &: (Integer) -> Integer
  def |: (Integer) -> Integer
  def []: (Integer) -> Integer
  def <<: (Integer) -> Integer
  def floor: (Integer) -> Integer
  def **: (Integer) -> Integer
  def /: (Integer) -> Integer
       | (Float) -> Float
       | (Numeric) -> Numeric
  def ~: () -> Integer
end

class Float <: Numeric
  def *: (Float) -> Float
       | (Integer) -> Float
       | (Numeric) -> Numeric
  def -: (Float) -> Float
  def +: (Float) -> Float
       | (Numeric) -> Numeric
  def round: (Integer) -> (Float | Integer)
           | () -> Integer
  def floor: -> Integer
  def /: (Float) -> Float
       | (Integer) -> Float
       | (Numeric) -> Numeric
end

Math::PI: Float

class Complex <: Numeric
  def self.polar: (Numeric, Numeric) -> instance
  def +: (Complex) -> Complex
       | (Numeric) -> Numeric
  def conjugate: -> Complex
  def *: (Complex) -> Complex
       | (Numeric) -> Numeric
  def real: -> Float
end

class Range<'a>
  def begin: -> 'a
  def end: -> 'a
  def map: <'b> { ('a) -> 'b } -> Array<'b>
  def all?: { ('a) -> any } -> any
  def max_by: { ('a) -> any } -> 'a
  def to_a: -> Array<'a>
end

class String
  def +: (String) -> String
  def to_str: -> String
  def size: -> Integer
  def bytes: -> Array<Integer>
  def %: (any) -> String
  def <<: (String) -> self
  def chars: -> Array<String>
  def slice!: (Integer) -> String
            | (Integer, Integer) -> String
            | (String) -> String
            | (Regexp, ?Integer) -> String
            | (Range<Integer>) -> String
  def unpack: (String) -> Array<any>
  def b: -> String
  def downcase: -> String
  def bytes: -> Array<Integer>
  def split: (String) -> Array<String>
           | (Regexp) -> Array<String>
end

class Enumerator<'a>
  def with_object: <'b> ('b) { ('a, 'b) -> any } -> 'b
  def with_index: { ('a, Integer) -> any } -> self
end

class Regexp
end

class File
  def self.binread: (String) -> String
  def self.extname: (String) -> String
  def self.basename: (String) -> String
  def self.readable?: (String) -> _Boolean
  def self.binwrite: (String, String) -> void
  def self.read: (String) -> String
end
