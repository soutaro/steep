require "test_helper"

class TypeAssignabilityTest < Minitest::Test
  T = Steep::Types
  Parser = Steep::Parser

  include TestHelper

  def parse_signature(src, &block)
    Parser.parse_signature(src).each(&block)
  end

  def test_any_any
    assignability = Steep::TypeAssignability.new
    assert assignability.test(src: T::Any.new, dest: T::Any.new)
  end

  def test_if1
    if1, if2 = Parser.parse_signature(<<-EOS)
interface _Foo
end

interface _Bar
end
    EOS

    assignability = Steep::TypeAssignability.new do |a|
      a.add_signature if1
      a.add_signature if2
    end

    assert assignability.test(src: T::Name.interface(name: :_Foo), dest: T::Name.interface(name: :_Bar))
  end

  def test_if2
    if1, if2 = Parser.parse_signature(<<-EOS)
interface _Foo
  def foo: -> any
end

interface _Bar
  def foo: -> any
end
    EOS

    assignability = Steep::TypeAssignability.new do |a|
      a.add_signature if1
      a.add_signature if2
    end

    assert assignability.test(src: T::Name.interface(name: :_Foo), dest: T::Name.interface(name: :_Bar))
  end

  def test_method1
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _A
  def foo: -> any
end

interface _B
  def bar: -> any
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test_method(parse_method_type("(_A) -> any"), parse_method_type("(_A) -> any"), [])
    assert assignability.test_method(parse_method_type("(_A) -> any"), parse_method_type("(any) -> any"), [])
    assert assignability.test_method(parse_method_type("(any) -> any"), parse_method_type("(_A) -> any"), [])
    refute assignability.test_method(parse_method_type("() -> any"), parse_method_type("(_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(_A) -> any"), parse_method_type("(_B) -> any"), [])

    assert assignability.test_method(parse_method_type("(_A, ?_B) -> any"), parse_method_type("(_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(_A) -> any"), parse_method_type("(_A, ?_B) -> any"), [])

    refute assignability.test_method(parse_method_type("(_A, ?_A) -> any"), parse_method_type("(*_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(_A, ?_A) -> any"), parse_method_type("(*_B) -> any"), [])

    assert assignability.test_method(parse_method_type("(*_A) -> any"), parse_method_type("(_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(*_A) -> any"), parse_method_type("(_B) -> any"), [])

    assert assignability.test_method(parse_method_type("(name: _A) -> any"), parse_method_type("(name: _A) -> any"), [])
    refute assignability.test_method(parse_method_type("(name: _A, email: _B) -> any"), parse_method_type("(name: _A) -> any"), [])

    assert assignability.test_method(parse_method_type("(name: _A, ?email: _B) -> any"), parse_method_type("(name: _A) -> any"), [])
    refute assignability.test_method(parse_method_type("(name: _A) -> any"), parse_method_type("(name: _A, ?email: _B) -> any"), [])

    refute assignability.test_method(parse_method_type("(name: _A) -> any"), parse_method_type("(name: _B) -> any"), [])

    assert assignability.test_method(parse_method_type("(**_A) -> any"), parse_method_type("(name: _A) -> any"), [])
    assert assignability.test_method(parse_method_type("(**_A) -> any"), parse_method_type("(name: _A, **_A) -> any"), [])
    assert assignability.test_method(parse_method_type("(name: _B, **_A) -> any"), parse_method_type("(name: _B, **_A) -> any"), [])

    refute assignability.test_method(parse_method_type("(name: _A) -> any"), parse_method_type("(**_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(email: _B, **B) -> any"), parse_method_type("(**_B) -> any"), [])
    refute assignability.test_method(parse_method_type("(**_B) -> any"), parse_method_type("(**_A) -> any"), [])
    refute assignability.test_method(parse_method_type("(name: _B, **_A) -> any"), parse_method_type("(name: _A, **_A) -> any"), [])
  end

  def test_method2
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _S
end

interface _T
  def foo: -> any
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test(src: T::Name.interface(name: :_T), dest: T::Name.interface(name: :_S))

    assert assignability.test_method(parse_method_type("() -> _T"), parse_method_type("() -> _S"), [])
    refute assignability.test_method(parse_method_type("() -> _S"), parse_method_type("() -> _T"), [])

    assert assignability.test_method(parse_method_type("(_S) -> any"), parse_method_type("(_T) -> any"), [])
    refute assignability.test_method(parse_method_type("(_T) -> any"), parse_method_type("(_S) -> any"), [])
  end

  def test_recursively
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _S
  def this: -> _S
end

interface _T
  def this: -> _T
  def foo: -> any
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test(src: T::Name.interface(name: :_T), dest: T::Name.interface(name: :_S))
    refute assignability.test(src: T::Name.interface(name: :_S), dest: T::Name.interface(name: :_T))
  end

  def test_union_intro
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _X
  def x: () -> any
end

interface _Y
  def y: () -> any
end

interface _Z
  def z: () -> any
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test(dest: T::Union.new(types: [T::Name.interface(name: :_X),
                                                         T::Name.interface(name: :_Y)]),
                              src: T::Name.interface(name: :_X))

    assert assignability.test(dest: T::Union.new(types: [T::Name.interface(name: :_X),
                                                         T::Name.interface(name: :_Y),
                                                         T::Name.interface(name: :_Z)]),
                              src: T::Union.new(types: [T::Name.interface(name: :_X),
                                                        T::Name.interface(name: :_Y)]))

    refute assignability.test(dest: T::Union.new(types: [T::Name.interface(name: :_X),
                                                         T::Name.interface(name: :_Y)]),
                              src: T::Name.interface(name: :_Z))
  end

  def test_union_elim
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _X
  def x: () -> any
  def z: () -> any
end

interface _Y
  def y: () -> any
  def z: () -> any
end

interface _Z
  def z: () -> any
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test(dest: T::Name.interface(name: :_Z),
                              src: T::Union.new(types: [T::Name.interface(name: :_X),
                                                        T::Name.interface(name: :_Y)]))

    refute assignability.test(dest: T::Name.interface(name: :_X),
                              src: T::Union.new(types: [T::Name.interface(name: :_Z),
                                                        T::Name.interface(name: :_Y)]))
  end

  def test_union_method
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-EOS).each do |interface|
interface _X
  def f: () -> any
       | (any) -> any
       | (any, any) -> any
end

interface _Y
  def f: () -> any
       | (_X) -> _X
end
      EOS
        a.add_signature interface
      end
    end

    assert assignability.test(src: T::Name.interface(name: :_X),
                              dest: T::Name.interface(name: :_Y))

    refute assignability.test(src: T::Name.interface(name: :_Y),
                              dest: T::Name.interface(name: :_X))
  end

  def test_add_signature
    klass, mod, interface, basic_object, object = parse_signature(<<-SRC).to_a
class A
end

module B
end

interface _C
end

class BasicObject
end

class Object <: BasicObject
end
    SRC

    assignability = Steep::TypeAssignability.new do |a|
      a.add_signature(klass)
      a.add_signature(mod)
      a.add_signature(interface)
      a.add_signature(object)
      a.add_signature(basic_object)
    end

    assert_equal klass, assignability.signatures[:A]
    assert_equal mod, assignability.signatures[:B]
    assert_equal interface, assignability.signatures[:_C]
  end

  def test_add_signature_duplicated
    assert_raises RuntimeError do
      Steep::TypeAssignability.new do |a|
        parse_signature(<<-SRC) do |signature|
class A
end

module A
end

class BasicObject
end

class Object <: BasicObject
end
    SRC

          a.add_signature(signature)
        end
      end
    end
  end

  def test_block_args
    sigs = parse_signature(<<-SRC).to_a
interface _Object
  def to_s: -> any
end

interface _String
  def to_s: -> any
  def +: (_String) -> _String
end
    SRC

    assignability = Steep::TypeAssignability.new do |a|
      sigs.each do |sig|
        a.add_signature sig
      end
    end

    assert assignability.test_method(parse_method_type("{ (_String) -> any } -> any"),
                                     parse_method_type("{ (_Object) -> any } -> any"),
                                     [])

    refute assignability.test_method(parse_method_type("{ (_Object) -> any } -> any"),
                                     parse_method_type("{ (_String) -> any } -> any"),
                                     [])

    assert assignability.test_method(parse_method_type("{ (_Object) -> any } -> any"),
                                     parse_method_type("{ (_Object, _String) -> any } -> any"),
                                     [])

    assert assignability.test_method(parse_method_type("{ (_Object, _String) -> any } -> any"),
                                     parse_method_type("{ (_Object) -> any } -> any"),
                                     [])

    assert assignability.test_method(parse_method_type("{ (_Object, _String) -> any } -> any"),
                                     parse_method_type("{ (_Object, *_Object) -> any } -> any"),
                                     [])

    refute assignability.test_method(parse_method_type("{ (_Object, _Object) -> any } -> any"),
                                     parse_method_type("{ (_Object, *_String) -> any } -> any"),
                                     [])
  end

  def test_validate_unknown_type_name
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-SRC) do |sig|
class BasicObject
end

class Symbol
end

class Object <: BasicObject
end

class SomeClass <: BasicObject
  def foo: (T1, ?T2, *T3, a: T4, ?b: T5, **T6) { (T7, ?T8, *T9) -> T10 } -> T11
end
      SRC
        a.add_signature sig
      end
    end

    assert_equal 11, assignability.errors.size

    %i(T1 T2 T3 T4 T5 T6 T7 T8 T9 T10 T11).each do |name|
      assert_any assignability.errors do |error|
        error.is_a?(Steep::Signature::Errors::UnknownTypeName) &&
          error.type == Steep::Types::Name.instance(name: name) &&
          error.signature.name == :SomeClass
      end
    end
  end

  def test_validate_incompatible_override
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-SRC) do |sig|
class BasicObject
end

class Object <: BasicObject
  def to_s: () -> String
end

class String
  def to_str: -> String
end

class Integer
  def to_int: -> Integer
end

class Symbol
end

class A
  def foo: (Object) -> any
  def bar: (String) -> any
end

class B <: A
  def foo: (String) -> any
  def bar: (Object) -> any
end
      SRC
        a.add_signature sig
      end
    end

    assert_equal 1, assignability.errors.size

    assert_any assignability.errors do |error|
      error.is_a?(Steep::Signature::Errors::IncompatibleOverride) &&
        error.method_name == :foo &&
        error.this_method == [parse_method_type("(String) -> any")] &&
        error.super_method == [parse_method_type("(Object) -> any")]
    end

    refute_any assignability.errors do |error|
      error.is_a?(Steep::Signature::Errors::IncompatibleOverride) &&
        error.method_name == :bar
    end
  end

  def test_self_type_validation
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-SRC) do |sig|
class BasicObject
end

interface _Each<'a>
  def each: { ('a) -> any } -> instance
end

class Object <: BasicObject
end

class Integer
end

module Enumerable<'a> : _Each<'a>
  def size: -> Integer
  def first: -> 'a
end

class A
  include Enumerable<Integer>
end
      SRC
        a.add_signature sig
      end
    end

    assert_equal 1, assignability.errors.size

    assert_any assignability.errors do |error|
      error.is_a?(Steep::Signature::Errors::InvalidSelfType) &&
        error.member.is_a?(Steep::Signature::Members::Include) &&
        error.member.name == Steep::Types::Name.instance(name: :Enumerable,
                                                         params: [Steep::Types::Name.instance(name: :Integer)])
    end
  end

  def test_compact
    assignability = Steep::TypeAssignability.new do |a|
      parse_signature(<<-SRC) do |sig|
interface _A
end

interface _B
end

interface _C
  def foo: -> _A
end

interface _D
  def foo: -> _A
  def bar: -> _B
end

interface _E
  def baz: -> _A
end
    SRC
        a.add_signature sig
      end
    end

    a = Steep::Types::Name.interface(name: :_A)
    b = Steep::Types::Name.interface(name: :_B)
    c = Steep::Types::Name.interface(name: :_C)
    d = Steep::Types::Name.interface(name: :_D)
    e = Steep::Types::Name.interface(name: :_E)

    assert_equal [a], assignability.compact([a, b])
    assert_equal [a], assignability.compact([a, b, c, d, e])
    assert_equal [c], assignability.compact([c, d])
    assert_equal [c, e], assignability.compact([c, d, e])
  end
end
