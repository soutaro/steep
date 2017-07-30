require "test_helper"

class TypeAssignabilityTest < Minitest::Test
  T = Steep::Types
  Parser = Steep::Parser

  def parse_method(src)
    Parser.parse_method(src)
  end

  def parse_interface(src, &block)
    Parser.parse_interfaces(src).each(&block)
  end

  def test_any_any
    assignability = Steep::TypeAssignability.new
    assert assignability.test(src: T::Any.new, dest: T::Any.new)
  end

  def test_if1
    if1, if2 = Parser.parse_interfaces(<<-EOS)
interface Foo
end

interface Bar
end
    EOS

    assignability = Steep::TypeAssignability.new
    assignability.add_interface if1
    assignability.add_interface if2

    assert assignability.test(src: T::Name.interface(name: :Foo), dest: T::Name.interface(name: :Bar))
  end

  def test_if2
    if1, if2 = Parser.parse_interfaces(<<-EOS)
interface Foo
  def foo: -> any
end

interface Bar
  def foo: -> any
end
    EOS

    assignability = Steep::TypeAssignability.new
    assignability.add_interface if1
    assignability.add_interface if2

    assert assignability.test(src: T::Name.interface(name: :Foo), dest: T::Name.interface(name: :Bar))
  end

  def test_method1
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface A
  def foo: -> any
end

interface B
  def bar: -> any
end
    EOS
      a.add_interface interface
    end

    assert a.test_method(parse_method("(A) -> any"), parse_method("(A) -> any"), [])
    assert a.test_method(parse_method("(A) -> any"), parse_method("(any) -> any"), [])
    assert a.test_method(parse_method("(any) -> any"), parse_method("(A) -> any"), [])
    refute a.test_method(parse_method("() -> any"), parse_method("(A) -> any"), [])
    refute a.test_method(parse_method("(A) -> any"), parse_method("(B) -> any"), [])

    assert a.test_method(parse_method("(A, ?B) -> any"), parse_method("(A) -> any"), [])
    refute a.test_method(parse_method("(A) -> any"), parse_method("(A, ?B) -> any"), [])

    refute a.test_method(parse_method("(A, ?A) -> any"), parse_method("(*A) -> any"), [])
    refute a.test_method(parse_method("(A, ?A) -> any"), parse_method("(*B) -> any"), [])

    assert a.test_method(parse_method("(*A) -> any"), parse_method("(A) -> any"), [])
    refute a.test_method(parse_method("(*A) -> any"), parse_method("(B) -> any"), [])

    assert a.test_method(parse_method("(name: A) -> any"), parse_method("(name: A) -> any"), [])
    refute a.test_method(parse_method("(name: A, email: B) -> any"), parse_method("(name: A) -> any"), [])

    assert a.test_method(parse_method("(name: A, ?email: B) -> any"), parse_method("(name: A) -> any"), [])
    refute a.test_method(parse_method("(name: A) -> any"), parse_method("(name: A, ?email: B) -> any"), [])

    refute a.test_method(parse_method("(name: A) -> any"), parse_method("(name: B) -> any"), [])

    assert a.test_method(parse_method("(**A) -> any"), parse_method("(name: A) -> any"), [])
    assert a.test_method(parse_method("(**A) -> any"), parse_method("(name: A, **A) -> any"), [])
    assert a.test_method(parse_method("(name: B, **A) -> any"), parse_method("(name: B, **A) -> any"), [])

    refute a.test_method(parse_method("(name: A) -> any"), parse_method("(**A) -> any"), [])
    refute a.test_method(parse_method("(email: B, **B) -> any"), parse_method("(**B) -> any"), [])
    refute a.test_method(parse_method("(**B) -> any"), parse_method("(**A) -> any"), [])
    refute a.test_method(parse_method("(name: B, **A) -> any"), parse_method("(name: A, **A) -> any"), [])
  end

  def test_method2
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface S
end

interface T
  def foo: -> any
end
    EOS
      a.add_interface interface
    end

    assert a.test(src: T::Name.interface(name: :T), dest: T::Name.interface(name: :S))

    assert a.test_method(parse_method("() -> T"), parse_method("() -> S"), [])
    refute a.test_method(parse_method("() -> S"), parse_method("() -> T"), [])

    assert a.test_method(parse_method("(S) -> any"), parse_method("(T) -> any"), [])
    refute a.test_method(parse_method("(T) -> any"), parse_method("(S) -> any"), [])
  end

  def test_recursively
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface S
  def this: -> S
end

interface T
  def this: -> T
  def foo: -> any
end
    EOS
      a.add_interface interface
    end

    assert a.test(src: T::Name.interface(name: :T), dest: T::Name.interface(name: :S))
    refute a.test(src: T::Name.interface(name: :S), dest: T::Name.interface(name: :T))
  end

  def test_union_intro
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface X
  def x: () -> any
end

interface Y
  def y: () -> any
end

interface Z
  def z: () -> any
end
    EOS
      a.add_interface interface
    end

    assert a.test(dest: T::Union.new(types: [T::Name.interface(name: :X),
                                             T::Name.interface(name: :Y)]),
                  src: T::Name.interface(name: :X))

    assert a.test(dest: T::Union.new(types: [T::Name.interface(name: :X),
                                             T::Name.interface(name: :Y),
                                             T::Name.interface(name: :Z)]),
                  src: T::Union.new(types: [T::Name.interface(name: :X),
                                            T::Name.interface(name: :Y)]))

    refute a.test(dest: T::Union.new(types: [T::Name.interface(name: :X),
                                             T::Name.interface(name: :Y)]),
                  src: T::Name.interface(name: :Z))
  end

  def test_union_elim
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface X
  def x: () -> any
  def z: () -> any
end

interface Y
  def y: () -> any
  def z: () -> any
end

interface Z
  def z: () -> any
end
    EOS
      a.add_interface interface
    end

    assert a.test(dest: T::Name.interface(name: :Z),
                  src: T::Union.new(types: [T::Name.interface(name: :X),
                                            T::Name.interface(name: :Y)]))

    refute a.test(dest: T::Name.interface(name: :X),
                  src: T::Union.new(types: [T::Name.interface(name: :Z),
                                            T::Name.interface(name: :Y)]))
  end

  def test_union_method
    a = Steep::TypeAssignability.new

    parse_interface(<<-EOS).each do |interface|
interface X
  def f: () -> any
       : (any) -> any
       : (any, any) -> any
end

interface Y
  def f: () -> any
       : (X) -> X
end
    EOS
      a.add_interface interface
    end

    assert a.test(src: T::Name.interface(name: :X),
                  dest: T::Name.interface(name: :Y))

    refute a.test(src: T::Name.interface(name: :Y),
                  dest: T::Name.interface(name: :X))
  end
end
