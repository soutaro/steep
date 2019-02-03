class BasicObject
  def __id__: -> Integer
end

class Object < BasicObject
  include Kernel
  def tap: { (self) -> any } -> self
  def to_s: -> String
  def hash: -> Integer
  def eql?: (any) -> bool
  def ==: (any) -> bool
  def ===: (any) -> bool
  def !=: (any) -> bool
  def class: -> class
  def is_a?: (Module) -> bool
  def inspect: -> String
  def freeze: -> self
  def method: (Symbol) -> Method
  def yield_self: <'a>{ (self) -> 'a } -> 'a
  def dup: -> self
  def send: (Symbol, *any) -> any
  def __send__: (Symbol, *any) -> any
  def instance_variable_get: (Symbol) -> any
  def nil?: -> bool
  def !: -> bool
  def Array: (any) -> Array<any>
  def Hash: (any) -> Hash<any, any>
  def instance_eval: <'x> { (self) -> 'x } -> 'x
                   | (String, ?String, ?Integer) -> any
  def define_singleton_method: (Symbol | String, any) -> Symbol
                             | (Symbol) { (*any) -> any } -> Symbol
end

class Module
  def attr_reader: (*any) -> any
  def class: -> any
  def module_function: (*Symbol) -> any
                     | -> any
  def extend: (Module) -> any
  def attr_accessor: (*Symbol) -> any
  def attr_writer: (*Symbol) -> any
  def include: (Module) -> bool
  def prepend: (Module) -> bool
end

class Method
end

class Class < Module
  def class: -> Class.class
  def allocate: -> any
end

module Kernel
  def raise: () -> any
           | (String) -> any
           | (*any) -> any

  def block_given?: -> bool
  def enum_for: (Symbol, *any) -> any
  def require_relative: (*String) -> void
  def require: (*String) -> void
  def loop: { () -> void } -> void
  def puts: (*any) -> void
  def eval: (String, ? Integer?, ?String) -> any
  def Integer: (String, Integer) -> Integer
             | (_ToI | _ToInt) -> Integer
end

class Array<'a>
  include Enumerable<'a, self>

  def initialize: (?Integer, ?'a) -> any
                | (self) -> any
                | (Integer) { (Integer) -> 'a } -> any

  def *: (Integer) -> self
       | (String) -> String
  def -: (self) -> self
  def +: (self) -> self
  def <<: ('a) -> self

  def []: (Integer) -> 'a
        | (Range<Integer>) -> self?
        | (0, Integer) -> self
        | (Integer, Integer) -> self?
  def at: (Integer) -> 'a
        | (Range<Integer>) -> self?
        | (Integer, Integer) -> self?
  def []=: (Integer, 'a) -> 'a
         | (Integer, Integer, 'a) -> 'a
         | (Integer, Integer, self) -> self
         | (Range<Integer>, 'a) -> 'a
         | (Range<Integer>, self) -> self

  def push: (*'a) -> self
  def append: (*'a) -> self

  def clear: -> self

  def collect!: { ('a) -> 'a } -> self
              | -> Enumerator<'a, self>
  def map!: { ('a) -> 'a } -> self
          | -> Enumerator<'a, self>

  def combination: (?Integer) { (self) -> any } -> Array<self>
                 | (?Integer) -> Enumerator<self, Array<self>>

  def empty?: -> bool
  def compact: -> self
  def compact!: -> self?
  def concat: (*Array<'a>) -> self
            | (*'a) -> self
  def delete: ('a) -> 'a?
            | <'x> ('a) { () -> 'x } -> ('a | 'x)
  def delete_at: (Integer) -> 'a?
  def delete_if: { ('a) -> any } -> self
               | -> Enumerator<'a, self>
  def reject!: { ('a) -> any } -> self?
             | -> Enumerator<'a, self?>
  def dig: (Integer, any) -> any
  def each: { ('a) -> any } -> self
          | -> Enumerator<'a, self>
  def each_index: { (Integer) -> any } -> self
                | -> Enumerator<Integer, self>
  def fetch: (Integer) -> 'a
           | (Integer, 'a) -> 'a
           | (Integer) { (Integer) -> 'a } -> 'a
  def fill: ('a) -> self
          | { (Integer) -> 'a } -> self
          | ('a, Integer, ?Integer?) -> self
          | ('a, Range<Integer>) -> self
          | (Integer, ?Integer?) { (Integer) -> 'a} -> self
          | (Range<Integer>) { (Integer) -> 'a } -> self

  def find_index: ('a) -> Integer?
                | { ('a) -> any } -> Integer?
                | -> Enumerator<'a, Integer?>

  def index: ('a) -> Integer?
           | { ('a) -> any } -> Integer?
           | -> Enumerator<'a, Integer?>

  def flatten: (?Integer?) -> Array<any>
  def flatten!: (?Integer?) -> self?

  def insert: (Integer, *'a) -> self

  def join: (any) -> String

  def keep_if: { ('a) -> any } -> self
             | -> Enumerator<'a, self>

  def last: -> 'a?
          | (Integer) -> self

  def length: -> Integer
  def size: -> Integer

  def pack: (String, ?buffer: String) -> String

  def permutation: (?Integer) { (self) -> any } -> Array<self>
                 | (?Integer) -> Enumerator<self, Array<self>>

  def pop: -> 'a?
         | (Integer) -> self

  def unshift: (*'a) -> self
  def prepend: (*'a) -> self

  def product: (*Array<'a>) -> Array<Array<'a>>
             | (*Array<'a>) { (Array<'a>) -> any } -> self

  def rassoc: (any) -> any

  def repeated_combination: (Integer) { (self) -> any } -> self
                          | (Integer) -> Enumerator<self, self>

  def repeated_permutation: (Integer) { (self) -> any } -> self
                          | (Integer) -> Enumerator<self, self>

  def replace: (self) -> self

  def reverse: -> self
  def reverse!: -> self

  def rindex: ('a) -> Integer?
            | { ('a) -> any } -> Integer?
            | -> Enumerator<'a, Integer?>

  def rotate: (?Integer) -> self

  def rotate!: (?Integer) -> self

  def sample: (?random: any) -> 'a?
            | (Integer, ?random: any) -> self

  def select!: -> Enumerator<'a, self>
             | { ('a) -> any } -> self

  def shift: -> 'a?
           | (Integer) -> self

  def shuffle: (?random: any) -> self

  def shuffle!: (?random: any) -> self

  def slice: (Integer) -> 'a?
           | (Integer, Integer) -> self?
           | (Range<Integer>) -> self?

  def slice!: (Integer) -> 'a?
            | (Integer, Integer) -> self?
            | (Range<Integer>) -> self?

  def to_h: -> Hash<any, any>

  def transpose: -> self

  def uniq!: -> self?
           | { ('a) -> any } -> self?

  def values_at: (*Integer | Range<Integer>) -> self

  def zip: <'x> (Array<'x>) -> Array<any>
         | <'x, 'y> (Array<'x>) { ('a, 'x) -> 'y }-> Array<'y>
end

class Hash<'key, 'value>
  def []: ('key) -> 'value?
  def []=: ('key, 'value) -> 'value
  def size: -> Integer
  def transform_values: <'a> { ('value) -> 'a } -> Hash<'key, 'a>
  def each_key: { ('key) -> any } -> instance
              | -> Enumerator<'a, self>
  def self.[]: (Array<any>) -> Hash<'key, 'value>
  def keys: () -> Array<'key>
  def each: { (['key, 'value]) -> any } -> self
          | -> Enumerator<['key, 'value], self>
  def key?: ('key) -> bool
  def merge: (Hash<'key, 'value>) -> Hash<'key, 'value>
  def delete: ('key) -> 'value?
  def each_value: { ('value) -> void } -> self
                | -> Enumerator<'valud, self>
  def empty?: -> bool

  include Enumerable<['key, 'value], self>
end

class Symbol
  def self.all_symbols: -> Array<Symbol>
end

interface _ToS
  def to_s: -> String
end

interface _ToI
  def to_i: -> Integer
end

interface _ToInt
  def to_int: -> Integer
end

class TrueClass
  def !: -> bool
end

class FalseClass
  def !: -> bool
end

class NilClass
end

class Numeric
  def +: (Numeric) -> Numeric
  def /: (Numeric) -> Numeric
  def <=: (any) -> bool
  def >=: (any) -> bool
  def < : (any) -> bool
  def >: (any) -> bool
  def -@: -> self
end

class Integer < Numeric
  def to_i: -> Integer
  def to_int: -> Integer
  def +: (Integer) -> Integer
       | (Numeric) -> Numeric
  def ^: (Numeric) -> Integer
  def *: (Integer) -> Integer
       | (Float) -> Float
       | (Numeric) -> Numeric
  def >>: (Integer) -> Integer
  def step: (Integer, ?Integer) { (Integer) -> any } -> self
          | (Integer, ?Integer) -> Enumerator<Integer, self>
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

class Float < Numeric
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

class Complex < Numeric
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
  def []: (Range<Integer>) -> String
        | (Integer, Integer) -> String
  def to_sym: -> Symbol
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
  def gsub: (Regexp, String) -> self
          | (String, String) -> self
          | (Regexp) { (String) -> _ToS } -> String
  def gsub!: (Regexp, String) -> self
           | (String, String) -> self
           | (Regexp) { (String) -> _ToS } -> String
  def sub: (Regexp | String, String) -> self
         | (Regexp | String) { (String) -> _ToS } -> String
  def chomp: -> String
           | (String) -> String
  def *: (Integer) -> String
  def scan: (Regexp) { (Array<String>) -> void } -> String
          | (Regexp) -> Array<String>
  def lines: -> Array<String>
  def bytesize: -> Integer
  def start_with?: (String) -> bool
  def byteslice: (Integer, Integer) -> String
  def empty?: -> bool
  def length: -> Integer
  def force_encoding: (any) -> self
  def to_i: -> Integer
          | (Integer) -> Integer
  def end_with?: (*String) -> bool
end

interface _Iteratable<'a, 'b>
  def each: () { ('a) -> void } -> 'b
end

module Enumerable<'a, 'b> : _Iteratable<'a, 'b>
  def all?: -> bool
          | { ('a) -> any } -> bool
          | (any) -> bool

  def any?: -> bool
          | { ('a) -> any } -> bool
          | (any) -> bool

  def chunk: { ('a) -> any } -> Enumerator<'a, self>

  def chunk_while: { ('a, 'a) -> any } -> Enumerator<'a, 'b>

  def collect: <'x> { ('a) -> 'x } -> Array<'x>
             | <'x> -> Enumerator<'a, Array<'x>>

  alias map collect
  
  def flat_map: <'x> { ('a) -> Array<'x> } -> Array<'x>
              | <'x> -> Enumerator<'a, Array<'x>>

  def collect_concat: <'x> { ('a) -> Array<'x> } -> Array<'x>
                    | <'x> -> Enumerator<'a, Array<'x>>

  def count: -> Integer
           | (any) -> Integer
           | { ('a) -> any } -> Integer

  def cycle: (?Integer) -> Enumerator<'a, nil>
           | (?Integer) { ('a) -> any } -> nil

  def detect: ('a) { ('a) -> any } -> 'a
            | { ('a) -> any } -> 'a?
            | -> Enumerator<'a, 'a?>
            | ('a) -> Enumerator<'a, 'a>

  def find: ('a) { ('a) -> any } -> 'a
          | { ('a) -> any } -> 'a?
          | -> Enumerator<'a, 'a?>
          | ('a) -> Enumerator<'a, 'a>

  def drop: (Integer) -> Array<'a>

  def drop_while: -> Enumerator<'a, Array<'a>>
                | { ('a) -> any } -> Array<'a>

  def each_cons: (Integer) -> Enumerator<Array<'a>, nil>
               | (Integer) { (Array<'a>) -> any } -> nil

  def each_entry: -> Enumerator<'a, self>
                | { ('a) -> any } -> self

  def each_slice: (Integer) -> Enumerator<Array<'a>, nil>
                | (Integer) { (Array<'a>) -> any } -> nil

  def each_with_index: { ('a, Integer) -> any } -> self

  def each_with_object: <'x> ('x) { ('a, 'x) -> any } -> 'x

  def to_a: -> Array<'a>
  def entries: -> Array<'a>

  def find_all: -> Enumerator<'a, Array<'a>>
              | { ('a) -> any } -> Array<'a>
  def select: -> Enumerator<'a, Array<'a>>
            | { ('a) -> any } -> Array<'a>

  def find_index: (any) -> Integer?
                | { ('a) -> any } -> Integer?
                | -> Enumerator<'a, Integer?>

  def first: () -> 'a?
           | (Integer) -> Array<'a>

  def grep: (any) -> Array<'a>
          | <'x> (any) { ('a) -> 'x } -> Array<'x>

  def grep_v: (any) -> Array<'a>
            | <'x> (any) { ('a) -> 'x } -> Array<'x>

  def group_by: <'x> { ('a) -> 'x } -> Hash<'x, Array<'a>>

  def member?: (any) -> bool
  def include?: (any) -> bool

  def inject: <'x> ('x) { ('x, 'a) -> 'x } -> 'x
            | (Symbol) -> any
            | (any, Symbol) -> any
            | { ('a, 'a) -> 'a } -> 'a


  def reduce: <'x> ('x) { ('x, 'a) -> 'x } -> 'x
            | (Symbol) -> any
            | (any, Symbol) -> any
            | { ('a, 'a) -> 'a } -> 'a

  def max: -> 'a?
         | (Integer) -> Array<'a>
         | { ('a, 'a) -> Integer } -> 'a?
         | (Integer) { ('a, 'a) -> Integer } -> Array<'a>

  def max_by: { ('a, 'a) -> Integer } -> 'a?
            | (Integer) { ('a, 'a) -> Integer } -> Array<'a>

  def min: -> 'a?
         | (Integer) -> Array<'a>
         | { ('a, 'a) -> Integer } -> 'a?
         | (Integer) { ('a, 'a) -> Integer } -> Array<'a>

  def min_by: { ('a, 'a) -> Integer } -> 'a?
            | (Integer) { ('a, 'a) -> Integer } -> Array<'a>

  def min_max: -> Array<'a>
             | { ('a, 'a) -> Integer } -> Array<'a>

  def min_max_by: { ('a, 'a) -> Integer } -> Array<'a>

  def none?: -> bool
           | { ('a) -> any } -> bool
           | (any) -> bool

  def one?: -> bool
          | { ('a) -> any } -> bool
          | (any) -> bool

  def partition: { ('a) -> any } -> Array<Array<'a>>
               | -> Enumerator<'a, Array<Array<'a>>>

  def reject: { ('a) -> any } -> Array<'a>
            | -> Enumerator<'a, Array<'a>>

  def reverse_each: { ('a) -> void } -> self
                  | -> Enumerator<'a, self>

  def slice_after: (any) -> Enumerator<Array<'a>, nil>
                 | { ('a) -> any } -> Enumerator<Array<'a>, nil>

  def slice_before: (any) -> Enumerator<Array<'a>, nil>
                  | { ('a) -> any } -> Enumerator<Array<'a>, nil>

  def slice_when: { ('a, 'a) -> any } -> Enumerator<Array<'a>, nil>

  def sort: -> Array<'a>
          | { ('a, 'a) -> Integer } -> Array<'a>

  def sort_by: { ('a) -> any } -> Array<'a>
             | -> Enumerator<'a, Array<'a>>

  def sort_by!: { ('a) -> any } -> self
              | -> Enumerator<'a, self>

  def sum: () -> Numeric
         | (Numeric) -> Numeric
         | (any) -> any
         | (?any) { ('a) -> any } -> any

  def take: (Integer) -> Array<'a>

  def take_while: { ('a) -> any } -> Array<'a>
                | -> Enumerator<'a, Array<'a>>


  def to_h: -> Hash<any, any>

  def uniq: -> Array<'a>
          | { ('a) -> any } -> Array<'a>
end

class Enumerator<'a, 'b>
  include Enumerable<'a, 'b>
  def each: { ('a) -> any } -> 'b
  def with_object: <'x> ('x) { ('a, 'x) -> any } -> 'x
  def with_index: { ('a, Integer) -> any } -> 'b
                | -> Enumerator<['a, Integer], 'b>
end

class Encoding
end

class Regexp
  def self.compile: (String) -> Regexp
                  | (String, Integer) -> Regexp
                  | (String, bool) -> Regexp
                  | (Regexp) -> Regexp
  def self.escape: (String) -> String
  def self.last_match: -> MatchData?
                     | (Integer) -> String?
  def self.quote: (String) -> String
  def self.try_convert: (any) -> Regexp?
  def self.union: (*String) -> Regexp
                | (Array<String>) -> Regexp
                | (*Regexp) -> Regexp
                | (Array<Regexp>) -> Regexp

  def initialize: (String) -> any
                | (String, Integer) -> any
                | (String, bool) -> any
                | (Regexp) -> any
  def ===: (String) -> bool
  def =~: (String) -> Integer?
  def casefold?: -> bool
  def encoding: -> Encoding
  def fixed_encoding?: -> bool
  def match: (String) -> MatchData?
           | (String, Integer) -> MatchData?
           | <'a> (String) { (MatchData) -> 'a } -> ('a | nil)
           | <'a> (String, Integer) { (MatchData) -> 'a } -> ('a | nil)
  def match?: (String) -> bool
            | (String, Integer) -> bool
  def named_captures: -> Hash<String, Array<Integer>>
  def names: -> Array<String>
  def options: -> Integer
  def source: -> String
  def ~: -> Integer?
end

class MatchData
  def []: (Integer | String | Symbol) -> String?
        | (Integer, Integer) -> Array<String>
        | (Range<Integer>) -> Array<String>
  def begin: (Integer) -> Integer?
           | (String | Symbol) -> Integer
  def captures: -> Array<String>
  def end: (Integer | String | Symbol) -> Integer
  def length: -> Integer
  def named_captures: -> Hash<String, String?>
  def names: -> Array<String>
  def offset: (Integer | String | Symbol) -> [Integer, Integer]
  def post_match: -> String
  def pre_match: -> String
  def regexp: -> Regexp
  def size: -> Integer
  def string: -> String
  def to_a: -> Array<String>
  def values_at: (*(Integer | String | Symbol)) -> Array<String?>
end

class IO
  def gets: -> String?
  def puts: (*any) -> void
  def read: (Integer) -> String
  def write: (String) -> Integer
  def flush: () -> void
end

File::FNM_DOTMATCH: Integer

class File < IO
  def self.binread: (String) -> String
  def self.extname: (String) -> String
  def self.basename: (String) -> String
  def self.readable?: (String) -> bool
  def self.binwrite: (String, String) -> void
  def self.read: (String) -> String
               | (String, Integer?) -> String?
  def self.fnmatch: (String, String, Integer) -> bool
  def path: -> String
  def self.write: (String, String) -> void
  def self.chmod: (Integer, String) -> void
end

class Proc
  def []: (*any) -> any
  def call: (*any) -> any
  def ===: (*any) -> any
  def yield: (*any) -> any
  def arity: -> Integer
  def binding: -> any
  def curry: -> Proc
           | (Integer) -> Proc
  def lambda?: -> bool
  def parameters: -> Array<[(:req | :opt | :rest | :keyreq | :key | :keyrest | :block), Symbol]>
  def source_location: -> [String, Integer]?
  def to_proc: -> self
end

STDOUT: IO

class StringIO
  def initialize: (?String, ?String) -> any
  def puts: (*any) -> void
  def readline: () -> String
              | (String) -> String
  def write: (String) -> void
  def flush: () -> void
  def string: -> String
end

class Process::Status
  def &: (Integer) -> Integer
  def >>: (Integer) -> Integer
  def coredump: -> bool
  def exited?: -> bool
  def exitstatus: -> Integer?
  def pid: -> Integer
  def signaled?: -> bool
  def stopsig: -> Integer?
  def success?: -> bool
  def termsig: -> Integer?
  def to_i: -> Integer
  def to_int: -> Integer
end

module Marshal
  def self.load: (String) -> any
  def self.dump: (any) -> String
end

class Set<'a>
  def self.[]: <'x> (*'x) -> Set<'x>

  def initialize: (_Iteratable<'a, any>) -> any
                | <'x> (_Iteratable<'x, any>) { ('x) -> 'a } -> any
                | (?nil) -> any

  def intersection: (_Iteratable<'a, any>) -> self
  def &: (_Iteratable<'a, any>) -> self

  def union: (_Iteratable<'a, any>) -> self
  def +: (_Iteratable<'a, any>) -> self
  def |: (_Iteratable<'a, any>) -> self

  def difference: (_Iteratable<'a, any>) -> self
  def -: (_Iteratable<'a, any>) -> self

  def add: ('a) -> self
  def <<: ('a) -> self
  def add?: ('a) -> self?

  def member?: (any) -> bool
  def include?: (any) -> bool

  def ^: (_Iteratable<'a, any>) -> self

  def classify: <'x> { ('a) -> 'x } -> Hash<'x, self>

  def clear: -> self

  def collect!: { ('a) -> 'a } -> self
  alias map! collect!

  def delete: (any) -> self
  def delete?: (any) -> self?

  def delete_if: { ('a) -> any } -> self
  def reject!: { ('a) -> any } -> self

  def disjoint?: (self) -> bool

  def divide: { ('a, 'a) -> any } -> Set<self>
            | { ('a) -> any } -> Set<self>

  def each: { ('a) -> void } -> self

  def empty?: -> bool

  def flatten: -> Set<any>

  def intersect?: -> bool

  def keep_if: { ('a) -> any } -> self

  def size: -> Integer
  alias length size

  def merge: (_Iteratable<'a, any>) -> self

  def subset?: (self) -> bool
  def proper_subst?: (self) -> bool

  def superset?: (self) -> bool
  def proper_superset?: (self) -> bool

  def replace: (_Iteratable<'a, any>) -> self

  def reset: -> self

  def select!: { ('a) -> any } -> self?

  def subtract: (_Iteratable<'a, any>) -> self

  def to_a: -> Array<'a>

  include Enumerable<'a, self>
end
