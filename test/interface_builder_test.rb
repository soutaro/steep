require_relative "test_helper"

class InterfaceBuilderTest < Minitest::Test
  include TestHelper

  Interface = Steep::Interface
  Substitution = Steep::Interface::Substitution
  Builder = Steep::Interface::Builder
  Types = Steep::AST::Types
  TypeName = Steep::TypeName
  ModuleName = Steep::ModuleName
  Signature = Steep::AST::Signature

  def test_method_type_to_method_type
    builder = Steep::Interface::Builder.new(signatures: {})

    method = Steep::Parser.parse_method("<'a, 'b> (::T0, ?::T1, *::T2, name: ::T3, ?email: ::T4, **::T5) { (::T6, ?::T7, *::T8) -> ::T9 } -> any")
    method_type = builder.method_type_to_method_type(method, current: nil)

    assert_instance_of Steep::Interface::MethodType, method_type

    assert_equal [:a, :b], method_type.type_params

    assert_equal [Types::Name.new_instance(name: "::T0")], method_type.params.required
    assert_equal [Types::Name.new_instance(name: "::T1")], method_type.params.optional
    assert_equal Types::Name.new_instance(name: "::T2"), method_type.params.rest
    assert_equal({ name: Types::Name.new_instance(name: "::T3") }, method_type.params.required_keywords)
    assert_equal({ email: Types::Name.new_instance(name: "::T4") }, method_type.params.optional_keywords)
    assert_equal Types::Name.new_instance(name: "::T5"), method_type.params.rest_keywords
    assert_equal Types::Any.new, method_type.return_type

    assert_equal [Types::Name.new_instance(name: "::T6")], method_type.block.params.required
    assert_equal [Types::Name.new_instance(name: "::T7")], method_type.block.params.optional
    assert_equal Types::Name.new_instance(name: "::T8"), method_type.block.params.rest
    assert_equal Types::Name.new_instance(name: "::T9"), method_type.block.return_type
  end

  def test_method_type_to_method_type2
    builder = Steep::Interface::Builder.new(signatures: {})

    method = Steep::Parser.parse_method(" -> any")
    method_type = builder.method_type_to_method_type(method, current: nil)

    assert_instance_of Steep::Interface::MethodType, method_type

    assert_empty method_type.type_params
    assert_empty method_type.params.required
    assert_empty method_type.params.optional
    assert_nil method_type.params.rest
    assert_empty method_type.params.required_keywords
    assert_empty method_type.params.optional_keywords
    assert_nil method_type.params.rest_keywords
    assert_nil method_type.block
    assert_equal Types::Any.new, method_type.return_type
  end

  def test_interface_to_interface
    i, _ = parse_signature(<<-EOF)
interface _Array<'a>
  def []: (Integer) -> 'a
  def each: { ('a) -> any } -> instance
          | -> Enumerable<'a>
end
    EOF

    builder = Builder.new(signatures: nil)
    interface = builder.interface_to_interface(TypeName::Interface.new(name: :_Array), i)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Interface.new(name: :_Array), interface.name
    assert_equal [:a], interface.params

    assert_equal 2, interface.methods.size
    interface.methods[:[]].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "(Integer) -> 'a", method.types[0].location.source
    end
    interface.methods[:each].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal 2, method.types.size
      assert_equal "{ ('a) -> any } -> instance", method.types[0].location.source
      assert_equal Types::Instance.new,
                   method.types[0].return_type
      assert_equal "-> Enumerable<'a>", method.types[1].location.source
    end
  end

  def test_module_instance_to_interface
     sigs = parse_signature(<<-EOF)
module A
  def foo: () -> Integer
  def bar: -> instance
  def self?.baz: -> module 
  def self.hoge: -> any
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    mod = env.find_module(ModuleName.parse(:A).absolute!)
    interface = builder.instance_to_interface(mod, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Instance.new(name: ModuleName.parse(:A).absolute!), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_nil method.super_method
      assert_equal "() -> Integer", method.types[0].location.source
    end
    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_nil method.super_method
      assert_equal "-> instance", method.types[0].location.source
      assert_equal Types::Instance.new, method.types[0].return_type
    end
    interface.methods[:baz].tap do |method|
      assert_instance_of Interface::Method, method
      assert_nil method.super_method
      assert_equal "-> module", method.types[0].location.source
      assert_equal Types::Class.new, method.types[0].return_type
    end
    assert_nil interface.methods[:hoge]
  end

  def test_module_instance_to_interface2
    sigs = parse_signature(<<-EOF)
module A
  def foo: () -> Integer
  def self.bar: -> String
end

module B
  include A
  def foo: () -> any
  def bar: (Integer) -> any
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    mod = env.find_module(ModuleName.parse(:B))
    interface = builder.instance_to_interface(mod, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Instance.new(name: ModuleName.parse(:B).absolute!), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> any", method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method
      assert_equal "() -> Integer", method.super_method.types[0].location.source
    end
    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "(Integer) -> any", method.types[0].location.source
      assert_nil method.super_method
    end
  end

  def test_class_instance_to_interface
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class A
  def foo: -> Integer
  def self.bar: -> any
  def self?.baz: -> String
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    klass = env.find_class(ModuleName.parse("::A"))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Instance.new(name: ModuleName.parse("::A")), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_nil method.super_method
      assert_equal "-> Integer", method.types[0].location.source
    end
    assert_nil interface.methods[:bar]
    interface.methods[:baz].tap do |method|
      assert_instance_of Interface::Method, method
      assert_nil method.super_method
      assert_equal "-> String", method.types[0].location.source
    end
  end

  def test_class_instance_to_interface_inheritance
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class A
  def foo: () -> A
end

class B <: A
  include C
  def foo: () -> B
end

module C
  def foo: () -> C
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    klass = env.find_class(ModuleName.parse("::B"))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Instance.new(name: ModuleName.parse("::B")), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> B", method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method
      assert_equal "() -> C", method.super_method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method.super_method
      assert_equal "() -> A", method.super_method.super_method.types[0].location.source
      assert_nil method.super_method.super_method.super_method
    end
  end

  def test_class_instance_to_interface_parameterized_inheritance_mixin
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class A<'a>
  def foo: () -> 'a
end

module B<'a>
  def bar: () -> 'a
end

class C <: A<String>
  include B<Integer>
end

class Integer
end

class String
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    klass = env.find_class(ModuleName.parse(:C))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Instance.new(name: ModuleName.parse("::C")), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> 'a", method.types[0].location.source
      assert_equal Types::Name.new_instance(name: "::String"), method.types[0].return_type
    end

    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> 'a", method.types[0].location.source
      assert_equal Types::Name.new_instance(name: "::Integer"), method.types[0].return_type
    end
  end

  def test_module_to_interface
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class Module
  def ancestors: -> Array<Module>
end

class String
end

class Numeric
end

interface _Boolean
end

class Symbol
end

module A
  include B
  extend C

  def foo: -> Integer
  def self.bar: -> String
  def self?.baz: -> Numeric
end

module B
  def self.bar: -> _Boolean
  def self.hoge: -> Symbol
end

module C
  def bar: -> Object
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    mod = env.find_module(ModuleName.parse(:A))
    interface = builder.module_to_interface(mod)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Module.new(name: ModuleName.parse("::A")), interface.name
    assert_empty interface.supers

    assert_nil interface.methods[:foo]

    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> String", method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method
      assert_equal "-> Object", method.super_method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method.super_method
      assert_equal "-> _Boolean", method.super_method.super_method.types[0].location.source
      assert_nil method.super_method.super_method.super_method
    end

    interface.methods[:baz].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> Numeric", method.types[0].location.source
      assert_nil method.super_method
    end

    interface.methods[:hoge].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> Symbol", method.types[0].location.source
      assert_nil method.super_method
    end

    interface.methods[:ancestors].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> Array<Module>", method.types[0].location.source
      assert_nil method.super_method
    end
  end

  def test_class_to_interface_no_constructor
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class Class<'a>
  def new: (*any, **any) -> 'a
end

class A
  def self.foo: -> Integer
  def self?.bar: -> Numeric
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    klass = env.find_class(ModuleName.parse(:A))
    interface = builder.class_to_interface(klass, constructor: nil)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Class.new(name: ModuleName.parse("::A"), constructor: nil), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> Integer", method.types[0].location.source
      assert_nil method.super_method
    end

    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> Numeric", method.types[0].location.source
      assert_nil method.super_method
    end

    assert_nil interface.methods[:new]
  end

  def test_class_to_interface_constructor
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class Class<'a>
  def new: (*any, **any) -> 'a
end

class A
  def initialize: (String) -> any
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)
    klass = env.find_class(ModuleName.parse(:A))
    interface = builder.class_to_interface(klass, constructor: true)

    assert_instance_of Interface::Abstract, interface
    assert_equal TypeName::Class.new(name: ModuleName.parse("::A"), constructor: true), interface.name
    assert_empty interface.supers

    interface.methods[:new].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal TypeName::Class.new(name: ModuleName.parse("::A"), constructor: true), method.type_name
      assert_equal "(String) -> any", method.types[0].location.source
      assert_equal Types::Instance.new, method.types[0].return_type
      assert_nil method.super_method
    end
  end

  def test_recursive_definition_error
    sigs = parse_signature(<<-EOF)
module A
  include B
end

module B
  include A
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)

    assert_raises Builder::RecursiveDefinitionError do
      builder.build(TypeName::Instance.new(name: ModuleName.parse(:A)))
    end
  end

  def test_instance_with_extension
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

extension Object (Pathname)
  def pathname: (any) -> any
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)

    sig = env.find_class(ModuleName.parse(:Object))
    interface = builder.instance_to_interface(sig, with_initialize: false)

    assert_instance_of Interface::Abstract, interface

    interface.methods[:pathname].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "(any) -> any", method.types[0].location.source
      assert_nil method.super_method
    end
  end

  def test_instance_variables
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class String
end

class Class
end

class Integer
end

class Module <: Class
end

module Bar
  @bar: Integer
end

class Foo
  include Bar
  @foo: String
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)

    klass = env.find_class(ModuleName.parse(:Foo))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Types::Name.new_instance(name: "::String"), interface.ivars[:"@foo"]
    assert_equal Types::Name.new_instance(name: "::Integer"), interface.ivars[:"@bar"]
  end

  def test_instance_variables2
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class String
end

class Class
end

class Foo
  @foo: String
end

class Bar <: Foo
  @foo: Integer
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)

    klass = env.find_class(ModuleName.parse(:Bar))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Types::Name.new_instance(name: "Integer"), interface.ivars[:"@foo"]
  end

  def test_instance_variables3
    sigs = parse_signature(<<-EOF)
class BasicObject
end

class Object <: BasicObject
end

class String
end

class Foo<'a>
  @foo: 'a
end
    EOF

    env = Signature::Env.new
    sigs.each do |sig|
      env.add sig
    end

    builder = Builder.new(signatures: env)

    klass = env.find_class(ModuleName.parse(:Foo))
    interface = builder.instance_to_interface(klass, with_initialize: false).instantiate(
      type: Types::Self.new,
      args: [Types::Var.new(name: :hoge)],
      instance_type: Types::Instance.new,
      module_type: Types::Class.new
    )

    assert_instance_of Interface::Instantiated, interface
    assert_equal Types::Var.new(name: :hoge), interface.ivars[:"@foo"]
  end
end
