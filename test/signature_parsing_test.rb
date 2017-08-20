require "test_helper"

class SignatureParsingTest < Minitest::Test
  include TestHelper

  def parse(src)
    Steep::Parser.parse_signature(src)
  end

  def method_type(src)
    Steep::Parser.parse_method(src)
  end

  def test_parsing_class
    klass, _ = parse(<<-EOS)
class C<'a> <: Object
  include M1
  extend M2

  def itself: () -> instance
  def class: () -> class
  def self.g: () -> C
  def self?.h: () -> C.class
end
    EOS

    assert_instance_of Steep::Signature::Class, klass
    assert_equal :C, klass.name
    assert_equal 6, klass.members.size
    assert_equal Steep::Types::Name.instance(name: :Object), klass.super_class
    assert_equal [:a], klass.params

    assert_equal Steep::Signature::Members::Include.new(name: Steep::Types::Name.instance(name: :M1)), klass.members[0]
    assert_equal Steep::Signature::Members::Extend.new(name: Steep::Types::Name.instance(name: :M2)), klass.members[1]
    assert_equal Steep::Signature::Members::InstanceMethod.new(name: :itself, types: [method_type("() -> instance")]), klass.members[2]
    assert_equal Steep::Signature::Members::InstanceMethod.new(name: :class, types: [method_type("() -> class")]), klass.members[3]
    assert_equal Steep::Signature::Members::ModuleMethod.new(name: :g, types: [method_type("() -> C")]), klass.members[4]
    assert_equal Steep::Signature::Members::ModuleInstanceMethod.new(name: :h, types: [method_type("() -> C.class")]), klass.members[5]
  end

  def test_parsing_module
    mod, _ = parse(<<-EOS)
module Kernel<'a>
  include M1
  extend M2

  def itself: () -> instance
  def class: () -> class
  def self.g: () -> C
  def self?.h: () -> C.class
end
    EOS

    assert_instance_of Steep::Signature::Module, mod
    assert_equal :Kernel, mod.name
    assert_equal 6, mod.members.size
    assert_equal [:a], mod.params
    assert_nil mod.self_type

    assert_equal Steep::Signature::Members::Include.new(name: Steep::Types::Name.instance(name: :M1)), mod.members[0]
    assert_equal Steep::Signature::Members::Extend.new(name: Steep::Types::Name.instance(name: :M2)), mod.members[1]
    assert_equal Steep::Signature::Members::InstanceMethod.new(name: :itself, types: [method_type("() -> instance")]), mod.members[2]
    assert_equal Steep::Signature::Members::InstanceMethod.new(name: :class, types: [method_type("() -> class")]), mod.members[3]
    assert_equal Steep::Signature::Members::ModuleMethod.new(name: :g, types: [method_type("() -> C")]), mod.members[4]
    assert_equal Steep::Signature::Members::ModuleInstanceMethod.new(name: :h, types: [method_type("() -> C.class")]), mod.members[5]
  end

  def test_parsing_module2
    mod, _ = parse(<<-EOS)
module Enumerable<'a> : _Enumerable<'a>
end
    EOS

    assert_instance_of Steep::Signature::Module, mod
    assert_equal :Enumerable, mod.name
    assert_empty mod.members
    assert_equal [:a], mod.params
    assert_equal Steep::Types::Name.interface(name: :_Enumerable,
                                              params: [Steep::Types::Var.new(name: :a)]), mod.self_type
  end

  def test_parsing_interface
    interface, _ = parse(<<-EOF)
interface _Foo<'a>
  def hello: -> any
  def +: (String) -> Bar
  def interface: -> Symbol   # Some comment
end
    EOF

    assert_instance_of Steep::Signature::Interface, interface
    assert_equal :_Foo, interface.name
    assert_equal [:a], interface.params
    assert_equal [parse_method("-> any")], interface.methods[:hello]
    assert_equal [parse_method("(String) -> Bar")], interface.methods[:+]
    assert_equal [parse_method("-> Symbol")], interface.methods[:interface]
  end

  def test_union_method_type
    interfaces = parse(<<-EOF)
interface _Kernel
  def gets: () -> String
          | () -> NilClass
end
    EOF

    assert_equal 1, interfaces.size

    interface = interfaces[0]
    assert_instance_of Steep::Signature::Interface, interface
    assert_equal :_Kernel, interface.name
    assert_equal [], interface.params
    assert_equal [parse_method("() -> String"),
                  parse_method("() -> NilClass")], interface.methods[:gets]

  end
end
