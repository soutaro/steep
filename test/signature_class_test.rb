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
end

class A<'x> <: B<'x>
  def foo: -> any
  def self.bar: -> any
  def self?.baz: -> any
end
    SRC

    klass = assignability.signatures[:A]

    methods = klass.instance_methods(assignability: assignability,
                                     klass: Types::Name.module(name: :A),
                                     instance: Types::Name.instance(name: :A),
                                     params: [Types::Name.instance(name: :String)])

    assert_equal [:itself, :to_s, :foo, :baz, :gets, :eval, :get].sort,
                 methods.keys.sort

    assert_equal [parse_method_type("-> String")], methods[:to_s]
    assert_equal [parse_method_type("-> any")], methods[:foo]
    assert_equal [parse_method_type("-> any")], methods[:baz]
    assert_equal [parse_method_type("-> A")], methods[:itself]
    assert_equal [parse_method_type("(String) -> any")], methods[:eval]
    assert_equal [parse_method_type("() -> String")], methods[:get]
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
                                   params: [])

    assert_equal [:foo, :bar, :new, :abs, :fizz, :hoge, :itself, :huga].sort,
                 methods.keys.sort

    assert_equal [parse_method_type("-> A")], methods[:foo]
    assert_equal [parse_method_type("-> A.class")], methods[:bar]
    assert_equal [parse_method_type("(String) -> A")], methods[:new]
    assert_equal [parse_method_type("(Number) -> Number")], methods[:abs]
    assert_equal [parse_method_type("-> String")], methods[:fizz]
    assert_equal [parse_method_type("-> any")], methods[:hoge]
    assert_equal [parse_method_type("-> String")], methods[:huga]
  end
end
