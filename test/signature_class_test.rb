require "test_helper"

class SignatureClassTest < Minitest::Test
  include TestHelper
  include Steep

  def new_assignability(src)
    TypeAssignability.new do |assignability|
      parse_signature(src).each do |signature|
        assignability.add_signature(signature)
      end
    end
  end

  def test_instance
    assignability = new_assignability(<<-SRC)
class BasicObject
  def itself: -> instance
end

module Kernel
  def gets: -> String
  def self.abc: -> any
  def self?.eval: (String) -> any 
end

class Object <: BasicObject
  include Kernel
  def to_s: -> String
end

class B<'a>
  def get: -> 'a
  def hoge: any -> any
end

class A<'x> <: B<'x>
  def foo: -> any
  def self.bar: -> any
  def self?.baz: -> any
  def hoge: (Integer) -> any
end
    SRC

    klass = assignability.signatures[:A]

    methods = klass.instance_methods(assignability: assignability,
                                     klass: Types::Name.module(name: :A),
                                     instance: Types::Name.instance(name: :A),
                                     params: [Types::Name.instance(name: :String)])

    assert_equal [:itself, :to_s, :foo, :baz, :gets, :eval, :get, :hoge].sort,
                 methods.keys.sort

    assert_equal parse_single_method("-> String"), methods[:to_s]
    assert_equal parse_single_method("-> any"), methods[:foo]
    assert_equal parse_single_method("-> any"), methods[:baz]
    assert_equal parse_single_method("-> A"), methods[:itself]
    assert_equal parse_single_method("(String) -> any"), methods[:eval]
    assert_equal parse_single_method("() -> String"), methods[:get]
    assert_equal parse_single_method("(Integer) -> any",
                                     super_method: parse_single_method("(any) -> any")),
                 methods[:hoge]
  end

  def test_module
    assignability = new_assignability(<<-SRC)
class BasicObject
  def itself: -> instance
end

class Object <: BasicObject
  def self.hoge: -> any
end

class Class<'a>
  def new: -> 'a
  def huga: -> String
end

class A
  include Math
  extend Bar

  def initialize: (String) -> any 
  def self.foo: -> instance
  def self?.bar: -> class
end

module Math
  def self?.abs: (Number) -> Number
end

module Bar
  def fizz: -> String
end
    SRC

    klass = assignability.signatures[:A]

    methods = klass.module_methods(assignability: assignability,
                                   klass: Types::Name.module(name: :A),
                                   instance: Types::Name.instance(name: :A),
                                   params: [],
                                   constructor: true)

    assert_equal [:foo, :bar, :new, :abs, :fizz, :hoge, :itself, :huga].sort,
                 methods.keys.sort

    assert_equal parse_single_method("-> A"), methods[:foo]
    assert_equal parse_single_method("-> A.class"), methods[:bar]
    assert_equal parse_single_method("(String) -> A"), methods[:new]
    assert_equal parse_single_method("(Number) -> Number"), methods[:abs]
    assert_equal parse_single_method("-> String"), methods[:fizz]
    assert_equal parse_single_method("-> any"), methods[:hoge]
    assert_equal parse_single_method("-> String"), methods[:huga]
  end

  def test_module_constructor
    assignability = new_assignability(<<-SRC)
class BasicObject
  def itself: -> instance
end

class Object <: BasicObject
  def self.hoge: -> any
end

class Class<'a>
  def huga: -> String
end

class A
  include Math
  extend Bar

  def initialize: (String) -> any 
  def self.foo: -> instance
  def self?.bar: -> class
end

module Math
  def self?.abs: (Number) -> Number
end

module Bar
  def fizz: -> String
end
    SRC

    klass = assignability.signatures[:A]

    methods = klass.module_methods(assignability: assignability,
                                   klass: Types::Name.module(name: :A),
                                   instance: Types::Name.instance(name: :A),
                                   params: [],
                                   constructor: false)

    assert_equal [:foo, :bar, :abs, :fizz, :hoge, :itself, :huga].sort,
                 methods.keys.sort

    assert_equal parse_single_method("-> A"), methods[:foo]
    assert_equal parse_single_method("-> A.class"), methods[:bar]
    assert_equal parse_single_method("(Number) -> Number"), methods[:abs]
    assert_equal parse_single_method("-> String"), methods[:fizz]
    assert_equal parse_single_method("-> any"), methods[:hoge]
    assert_equal parse_single_method("-> String"), methods[:huga]
  end

  def test_super
    assignability = new_assignability(<<-SRC)
class BasicObject
  def foo: (any) -> any
end

class Object <: BasicObject
end

class A
  def foo: (BasicObject) -> any
  include X
end

module X
  def foo: (Object) -> any
end
    SRC

    klass = assignability.signatures[:A]

    methods = klass.instance_methods(assignability: assignability,
                                     klass: Types::Name.module(name: :A),
                                     instance: Types::Name.instance(name: :A),
                                     params: [])

    assert_equal [:foo], methods.keys

    basic_object_foo = parse_single_method("(any) -> any")
    x_foo = parse_single_method("(Object) -> any", super_method: basic_object_foo)
    assert_equal parse_single_method("(BasicObject) -> any", super_method: x_foo), methods[:foo]
  end

  def test_extension
    assignability = new_assignability(<<-SRC)
class BasicObject
end

class Object <: BasicObject
end

class Pathname
end

extension Object (Pathname)
  def Pathname: (String) -> Pathname
end
    SRC

    klass = assignability.signatures[:Object]
    methods = klass.instance_methods(assignability: assignability,
                                     klass: Types::Name.module(name: :Object),
                                     instance: Types::Name.instance(name: :Object),
                                     params: [])

    assert_equal [:Pathname], methods.keys
  end

  def test_interface_with_constructor
    assignability = new_assignability(<<-SRC)
class BasicObject
end

class Object <: BasicObject
end

class A
  def (constructor) foo: (BasicObject) -> any
end

class B <: A
  def foo: (any) -> any
end
    SRC

    a_methods = assignability.signatures[:A].instance_methods(assignability: assignability,
                                                            klass: Types::Name.module(name: :A),
                                                            instance: Types::Name.instance(name: :A),
                                                            params: [])

    assert_equal [:foo], a_methods.keys
    assert_equal [:constructor], a_methods[:foo].attributes


    b_methods = assignability.signatures[:B].instance_methods(assignability: assignability,
                                                              klass: Types::Name.module(name: :B),
                                                              instance: Types::Name.instance(name: :B),
                                                              params: [])

    assert_equal [:foo], b_methods.keys
    assert_equal [:constructor], b_methods[:foo].attributes
  end
end
