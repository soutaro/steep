require_relative "test_helper"

class InterfaceBuilderTest < Minitest::Test
  include TestHelper

  Interface = Steep::Interface
  Substitution = Steep::Interface::Substitution
  Builder = Steep::Interface::Builder
  Types = Steep::AST::Types
  Names = Steep::Names
  Signature = Steep::AST::Signature
  Namespace = Steep::AST::Namespace

  def signatures(sigs = "")
    default = <<-EOF
class Integer
  def to_int: -> Integer
end
class String
  def to_str: -> String
end
class Class
  def new: (*any) -> any
end
class Object < BasicObject end
class BasicObject
  def initialize: () -> any
end
class Module
  def ancestors: -> any
end

class Numeric
end

class TrueClass
end

class FalseClass
end
class Symbol end
class T0 end
class T1 end
class T2 end
class T3 end
class T4 end
class T5 end
class T6 end
class T7 end
class T8 end
class T9 end
    EOF

    Signature::Env.new.tap do |signatures|
      parse_signature(default).each do |sig|
        signatures.add sig
      end

      parse_signature(sigs).each do |sig|
        signatures.add sig
      end
    end
  end

  def test_absolute_type
    signatures = signatures(<<-EOF)
class A
end

class A::B
end

module A::C
end
    EOF

    builder = Builder.new(signatures: signatures)

    assert_equal parse_type("::A"), builder.absolute_type(parse_type("::A"), current: Namespace.root)
    assert_equal parse_type("::A"), builder.absolute_type(parse_type("A"), current: Namespace.root)
    assert_equal parse_type("::A::B"), builder.absolute_type(parse_type("B"), current: Namespace.parse("::A"))
    assert_raises { builder.absolute_type(parse_type("B"), current: Namespace.root) }

    assert_equal parse_type("::A.class"), builder.absolute_type(parse_type("::A.class"), current: Namespace.root)
    assert_equal parse_type("::A.class constructor"), builder.absolute_type(parse_type("A.class constructor"), current: Namespace.root)
    assert_equal parse_type("::A::B.class"), builder.absolute_type(parse_type("B.class"), current: Namespace.parse("::A"))
    assert_raises { builder.absolute_type(parse_type("C.class"), current: Namespace.parse("::A")) }
    assert_raises { builder.absolute_type(parse_type("B.class"), current: Namespace.root) }

    assert_equal parse_type("::A.module"), builder.absolute_type(parse_type("::A.module"), current: Namespace.root)
    assert_equal parse_type("::A.module"), builder.absolute_type(parse_type("A.module"), current: Namespace.root)
    assert_equal parse_type("::A::B.module"), builder.absolute_type(parse_type("B.module"), current: Namespace.parse("::A"))
    assert_equal parse_type("::A::C.module"), builder.absolute_type(parse_type("C.module"), current: Namespace.parse("::A"))
    assert_raises { builder.absolute_type(parse_type("B.module"), current: Namespace.root) }
  end

  def test_method_type_to_method_type
    builder = Steep::Interface::Builder.new(signatures: signatures)

    method = Steep::Parser.parse_method("<'a, 'b> (::T0, ?::T1, *::T2, name: ::T3, ?email: ::T4, **::T5) { (::T6, ?::T7, *::T8) -> ::T9 } -> any")
    method_type = builder.method_type_to_method_type(method, current: Namespace.root)

    assert_instance_of Steep::Interface::MethodType, method_type

    assert_equal [:a, :b], method_type.type_params

    assert_equal [parse_type("::T0")], method_type.params.required
    assert_equal [parse_type("::T1")], method_type.params.optional
    assert_equal parse_type("::T2"), method_type.params.rest
    assert_equal({ name: parse_type("::T3") }, method_type.params.required_keywords)
    assert_equal({ email: parse_type("::T4") }, method_type.params.optional_keywords)
    assert_equal parse_type("::T5"), method_type.params.rest_keywords
    assert_equal parse_type("any"), method_type.return_type

    assert_equal [parse_type("::T6")], method_type.block.type.params.required
    assert_equal [parse_type("::T7")], method_type.block.type.params.optional
    assert_equal parse_type("::T8"), method_type.block.type.params.rest
    assert_equal parse_type("::T9"), method_type.block.type.return_type
  end

  def test_method_type_to_method_type2
    builder = Steep::Interface::Builder.new(signatures: signatures)

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
    signatures = self.signatures(<<-EOF)
class Enumerable<'a>
end

interface _Array<'a>
  def []: (Integer) -> 'a
  def each: { ('a) -> any } -> instance
          | -> Enumerable<'a>
end
    EOF

    builder = Builder.new(signatures: signatures)
    name = Names::Interface.new(name: :_Array, namespace: Namespace.root)
    interface = builder.interface_to_interface(name, signatures.find_interface(name))

    assert_instance_of Interface::Abstract, interface
    assert_equal name, interface.name
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
    signatures = signatures(<<-EOF)
module A
  def foo: () -> Integer
  def bar: -> instance
  def self?.baz: -> module 
  def self.hoge: -> any
end
    EOF

    builder = Builder.new(signatures: signatures)
    mod = signatures.find_module(Names::Module.parse("::A"))
    interface = builder.instance_to_interface(mod, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse(:A).absolute!, interface.name
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
    signatures = signatures(<<-EOF)
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

    builder = Builder.new(signatures: signatures)
    mod = signatures.find_module(Names::Module.parse(:B))
    interface = builder.instance_to_interface(mod, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse(:B).absolute!, interface.name
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
    signatures = signatures(<<-EOF)
class A
  def foo: -> Integer
  def self.bar: -> any
  def self?.baz: -> String
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse("::A"))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::A"), interface.name
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
    signatures = signatures(<<-EOF)
class A
  def foo: () -> A
end

class B < A
  include C
  def foo: () -> B
end

module C
  def foo: () -> C
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse("::B"))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::B"), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> ::B", method.types[0].to_s
      assert_instance_of Interface::Method, method.super_method
      assert_equal "() -> ::C", method.super_method.types[0].to_s
      assert_instance_of Interface::Method, method.super_method.super_method
      assert_equal "() -> ::A", method.super_method.super_method.types[0].to_s
      assert_nil method.super_method.super_method.super_method
    end
  end

  def test_class_instance_to_interface_parameterized_inheritance_mixin
    signatures = signatures(<<-EOF)
class A<'a>
  def foo: () -> 'a
end

module B<'a>
  def bar: () -> 'a
end

class C < A<String>
  include B<Integer>
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse("::C"))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::C"), interface.name
    assert_empty interface.supers

    interface.methods[:foo].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> 'a", method.types[0].location.source
      assert_equal "() -> ::String", method.types[0].to_s
    end

    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "() -> 'a", method.types[0].location.source
      assert_equal "() -> ::Integer", method.types[0].to_s
    end
  end

  def test_module_to_interface
    signatures = signatures(<<-EOF)
class Array<'a> end

module A
  include B
  extend C

  @name: String

  def foo: -> Integer
  def self.bar: -> String
  def self?.baz: -> Numeric
end

module B
  def self.bar: -> bool
  def self.hoge: -> Symbol
end

module C
  attr_accessor address: String
  def bar: -> Object
end
    EOF

    builder = Builder.new(signatures: signatures)
    mod = signatures.find_module(Names::Module.parse(:A))
    interface = builder.module_to_interface(mod)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::A"), interface.name
    assert_empty interface.supers

    assert_nil interface.methods[:foo]

    interface.methods[:bar].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "-> String", method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method
      assert_equal "-> Object", method.super_method.types[0].location.source
      assert_instance_of Interface::Method, method.super_method.super_method
      assert_equal "-> bool", method.super_method.super_method.types[0].location.source
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
      assert_equal "-> any", method.types[0].location.source
      assert_nil method.super_method
    end

    interface.methods[:address].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "String", method.types[0].location.source
      assert_nil method.super_method
    end

    interface.methods[:address=].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "String", method.types[0].location.source
      assert_nil method.super_method
    end

    assert_equal({ "@address": parse_type("::String"), "@name": parse_type("::String") },  interface.ivars)
  end

  def test_class_to_interface_no_constructor
    signatures = signatures(<<-EOF)
class A
  def self.foo: -> Integer
  def self?.bar: -> Numeric
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:A))
    interface = builder.class_to_interface(klass, constructor: nil)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::A"), interface.name
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

  def test_class_to_interface_initializer
    signatures = signatures(<<-EOF)
class Array<'a>
  def initialize: (Integer, 'a) -> any
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse("::Array"))
    interface = builder.class_to_interface(klass, constructor: true)

    assert_empty interface.params

    interface.methods[:new].types.yield_self do |types|
      assert_equal 1, types.size
      types.first.yield_self do |method_type|
        assert_equal "<'a> (::Integer, 'a) -> instance", method_type.to_s
      end
    end

    assert_equal [:incompatible], interface.methods[:new].attributes
  end

  def test_class_to_interface_initializer2
    signatures = signatures(<<-EOF)
class Array<'a>
  def initialize: <'b> (Integer) { (Integer, 'b) -> 'a } -> any
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse("::Array"))
    interface = builder.class_to_interface(klass, constructor: true)

    assert_empty interface.params

    interface.methods[:new].types.yield_self do |types|
      assert_equal 1, types.size
      types.first.yield_self do |method_type|
        assert_equal "<'a, 'b> (::Integer) { (::Integer, 'b) -> 'a } -> instance", method_type.to_s
      end
    end

    assert_equal [:incompatible], interface.methods[:new].attributes
  end

  def test_class_to_interface_constructor
    signatures = signatures(<<-EOF)
class A
  def initialize: (String) -> any
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:A))
    interface = builder.class_to_interface(klass, constructor: true)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::A"), interface.name
    assert_empty interface.supers

    interface.methods[:new].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal Names::Module.parse("::A"), method.type_name
      assert_equal "(String) -> any", method.types[0].location.source
      assert_equal "(::String) -> instance", method.types[0].to_s
      assert_equal Types::Instance.new, method.types[0].return_type
      assert_nil method.super_method
    end

    assert_equal [:incompatible], interface.methods[:new].attributes
  end

  def test_class_to_interface_no_initialize
    signatures = signatures(<<-EOF)
class A
end
    EOF

    builder = Builder.new(signatures: signatures)
    interface = builder.build_class(Names::Module.parse("::A"), constructor: true)

    assert_instance_of Interface::Abstract, interface
    assert_equal Names::Module.parse("::A"), interface.name
    assert_empty interface.supers

    interface.methods[:new].tap do |method|
      assert_equal ["() -> instance"], method.types.map(&:to_s)
    end

    assert_equal [:incompatible], interface.methods[:new].attributes
  end

  def test_recursive_definition_error
    signatures = signatures(<<-EOF)
module A
  include B
end

module B
  include A
end
    EOF

    builder = Builder.new(signatures: signatures)

    assert_raises Builder::RecursiveDefinitionError do
      builder.build_instance(Names::Module.parse("::A"), with_initialize: false)
    end
  end

  def test_instance_with_extension
    signatures = signatures(<<-EOF)
extension Object (Pathname)
  def pathname: (any) -> any
end
    EOF

    builder = Builder.new(signatures: signatures)

    sig = signatures.find_class(Names::Module.parse(:Object))
    interface = builder.instance_to_interface(sig, with_initialize: false)

    assert_instance_of Interface::Abstract, interface

    interface.methods[:pathname].tap do |method|
      assert_instance_of Interface::Method, method
      assert_equal "(any) -> any", method.types[0].location.source
      assert_nil method.super_method
    end
  end

  def test_instance_variables
    signatures = signatures(<<-EOF)
module Bar
  @bar: Integer
end

class Foo
  include Bar
  @foo: String
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:Foo))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Types::Name.new_instance(name: "::String"), interface.ivars[:"@foo"]
    assert_equal Types::Name.new_instance(name: "::Integer"), interface.ivars[:"@bar"]
  end

  def test_instance_variables2
    signatures = signatures(<<-EOF)
class Foo
  @foo: String
end

class Bar < Foo
  @foo: Integer
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:Bar))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Types::Name.new_instance(name: "::Integer"), interface.ivars[:"@foo"]
  end

  def test_instance_variables3
    signatures = signatures(<<-EOF)
class Foo<'a>
  @foo: 'a
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:Foo))
    interface = builder.instance_to_interface(klass, with_initialize: false).instantiate(
      type: Types::Self.new,
      args: [Types::Var.new(name: :hoge)],
      instance_type: Types::Instance.new,
      module_type: Types::Class.new
    )

    assert_instance_of Interface::Instantiated, interface
    assert_equal Types::Var.new(name: :hoge), interface.ivars[:"@foo"]
  end

  def test_ivar_validate
    signatures = signatures(<<-EOF)
class Foo
  @foo: String
end

class Bar < Foo
  @foo: String
end

class Baz < Foo
  @foo: Integer
end

class Hoge < Foo
  @foo: any
end
    EOF

    builder = Builder.new(signatures: signatures)
    checker = Steep::Subtyping::Check.new(builder: builder)

    signatures.find_class(Names::Module.parse(:Bar)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      instantiated = interface.instantiate(type: Types::Name.new_instance(name: "::Bar"),
                                           args: [],
                                           instance_type: Types::Name.new_instance(name: "::Bar"),
                                           module_type: Types::Name.new_class(name: "::Bar", constructor: false),
                                           )

      instantiated.validate(checker)
    end

    signatures.find_class(Names::Module.parse(:Baz)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      instantiated = interface.instantiate(type: Types::Name.new_instance(name: "::Baz"),
                                           args: [],
                                           instance_type: Types::Name.new_instance(name: "::Baz"),
                                           module_type: Types::Name.new_class(name: "::Baz", constructor: false),
                                           )

      assert_raises Interface::Instantiated::InvalidIvarOverrideError do
        instantiated.validate(checker)
      end
    end

    signatures.find_class(Names::Module.parse(:Hoge)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      instantiated = interface.instantiate(type: Types::Name.new_instance(name: "::Hoge"),
                                           args: [],
                                           instance_type: Types::Name.new_instance(name: "::Hoge"),
                                           module_type: Types::Name.new_class(name: "::Hoge", constructor: false),
                                           )

      assert_raises Interface::Instantiated::InvalidIvarOverrideError do
        instantiated.validate(checker)
      end
    end
  end

  def test_attributes
    signatures = signatures(<<-EOF)
class Hello
  attr_reader name: String
  attr_reader phone (): String
  attr_accessor address (@contact): String
end
    EOF

    builder = Builder.new(signatures: signatures)
    klass = signatures.find_class(Names::Module.parse(:Hello))
    interface = builder.instance_to_interface(klass, with_initialize: false)

    assert_instance_of Interface::Abstract, interface
    assert_equal Types::Name.new_instance(name: "::String"), interface.ivars[:@name]
    assert_nil interface.ivars[:@phone]
    assert_equal Types::Name.new_instance(name: "::String"), interface.ivars[:@contact]

    interface.methods[:name].yield_self do |method|
      assert_equal ["() -> ::String"], method.types.map(&:to_s)
    end
    interface.methods[:phone].yield_self do |method|
      assert_equal ["() -> ::String"], method.types.map(&:to_s)
    end
    interface.methods[:address].yield_self do |method|
      assert_equal ["() -> ::String"], method.types.map(&:to_s)
    end
    interface.methods[:address=].yield_self do |method|
      assert_equal ["(::String) -> ::String"], method.types.map(&:to_s)
    end
  end

  def test_incompatible_method
    signatures = signatures(<<-EOF)
class Hello
  def foo: () -> Integer
end

class World < Hello
  def (incompatible) foo: (Object) -> String 
end
    EOF

    builder = Builder.new(signatures: signatures)
    signatures.find_class(Names::Module.parse(:Hello)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      refute_operator interface.methods[:foo], :incompatible?
    end

    signatures.find_class(Names::Module.parse(:World)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      assert_operator interface.methods[:foo], :incompatible?
    end
  end

  def test_initialize_is_incompatible
    signatures = signatures(<<-EOF)
class Hello
  def initialize: (Integer) -> any
end
    EOF

    builder = Builder.new(signatures: signatures)

    signatures.find_class(Names::Module.parse(:Hello)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: true)
      assert_operator interface.methods[:initialize], :incompatible?
      refute_nil interface.methods[:initialize].super_method
    end
  end

  def test_initialize_is_private
    signatures = signatures(<<-EOF)
class Hello
  def initialize: (Integer) -> any
end
    EOF

    builder = Builder.new(signatures: signatures)

    signatures.find_class(Names::Module.parse(:Hello)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: true)
      assert_operator interface.methods[:initialize], :private?
      refute_nil interface.methods[:initialize].super_method
    end
  end

  def test_private_method_type
    signatures = signatures(<<-EOF)
class Hello
  def (private) puts: (String) -> void
end
    EOF

    builder = Builder.new(signatures: signatures)

    signatures.find_class(Names::Module.parse(:Hello)).yield_self do |klass|
      interface = builder.instance_to_interface(klass, with_initialize: false)
      assert_operator interface.methods[:puts], :private?
      assert_nil interface.methods[:puts].super_method
    end
  end

  def test_relative_include
    signatures = signatures(<<-EOF)
module A::B::C
end

class A::B::X
  include C
  extend C
end

module A::B::Y
  include C
  extend C
end
    EOF

    builder = Builder.new(signatures: signatures)

    signatures.find_class(Names::Module.parse("::A::B::X")).yield_self do |klass|
      builder.instance_to_interface(klass, with_initialize: true)
      builder.class_to_interface(klass, constructor: true)
    end

    signatures.find_module(Names::Module.parse("::A::B::Y")).yield_self do |klass|
      builder.instance_to_interface(klass, with_initialize: true)
      builder.module_to_interface(klass)
    end
  end
end
