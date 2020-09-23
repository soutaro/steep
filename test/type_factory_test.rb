require "test_helper"

class TypeFactoryTest < Minitest::Test
  def parse_type(str, variables: [])
    RBS::Parser.parse_type(str, variables: variables)
  end

  def parse_method_type(str)
    RBS::Parser.parse_method_type(str)
  end

  def assert_overload_with(c, *types)
    types = types.map do |s|
      factory.method_type(parse_method_type(s), self_type: Steep::AST::Types::Self.new, subst2: nil)
    end

    assert_equal Set.new(types), Set.new(c.method_types), "Expected: { #{types.join(" | ")} }, Actual: #{c.to_s}"
  end

  def assert_overload_including(c, *types)
    types = types.map do |s|
      factory.method_type(parse_method_type(s), self_type: Steep::AST::Types::Self.new, subst2: nil)
    end

    assert_operator Set.new(types),
                    :subset?, Set.new(c.method_types),
                    "Expected: { #{types.join(" | ")} } is a subset of { #{c.method_types.join(" | ")} }"
  end

  Types = Steep::AST::Types

  include TestHelper
  include FactoryHelper

  def test_type
    with_factory() do |factory|
      factory.type(parse_type("void")).yield_self do |type|
        assert_instance_of Types::Void, type
      end

      factory.type(parse_type("class")).yield_self do |type|
        assert_instance_of Types::Class, type
      end

      factory.type(parse_type("instance")).yield_self do |type|
        assert_instance_of Types::Instance, type
      end

      factory.type(parse_type("self")).yield_self do |type|
        assert_instance_of Types::Self, type
      end

      factory.type(parse_type("top")).yield_self do |type|
        assert_instance_of Types::Top, type
      end

      factory.type(parse_type("bot")).yield_self do |type|
        assert_instance_of Types::Bot, type
      end

      factory.type(parse_type("bool")).yield_self do |type|
        assert_instance_of Types::Boolean, type
      end

      factory.type(parse_type("nil")).yield_self do |type|
        assert_instance_of Types::Nil, type
      end

      factory.type(parse_type("singleton(::Object)")).yield_self do |type|
        assert_instance_of Types::Name::Singleton, type
        assert_equal "::Object", type.name.to_s
      end

      factory.type(parse_type("Array[Object]")).yield_self do |type|
        assert_instance_of Types::Name::Instance, type
        assert_equal "Array", type.name.to_s
        assert_equal ["Object"], type.args.map(&:to_s)
      end

      factory.type(parse_type("_Each[self, void]")).yield_self do |type|
        assert_instance_of Types::Name::Interface, type
        assert_equal "_Each", type.name.to_s
        assert_equal ["self", "void"], type.args.map(&:to_s)
      end

      factory.type(parse_type("Super::duper")).yield_self do |type|
        assert_instance_of Types::Name::Alias, type
        assert_equal "Super::duper", type.name.to_s
        assert_equal [], type.args
      end

      factory.type(parse_type("Integer | nil")).yield_self do |type|
        assert_instance_of Types::Union, type
        assert_equal ["Integer", "nil"].sort, type.types.map(&:to_s).sort
      end

      factory.type(parse_type("Integer & nil")).yield_self do |type|
        assert_instance_of Types::Intersection, type
        assert_equal ["Integer", "nil"].sort, type.types.map(&:to_s).sort
      end

      factory.type(parse_type("Integer?")).yield_self do |type|
        assert_instance_of Types::Union, type
        assert_equal ["Integer", "nil"].sort, type.types.map(&:to_s).sort
      end

      factory.type(parse_type("30")).yield_self do |type|
        assert_instance_of Types::Literal, type
        assert_equal 30, type.value
      end

      factory.type(parse_type("[Integer, String]")).yield_self do |type|
        assert_instance_of Types::Tuple, type
      end

      factory.type(parse_type("{ foo: bar }")).yield_self do |type|
        assert_instance_of Types::Record, type
        assert_operator type.elements, :key?, :foo
      end

      factory.type(parse_type("^(a, ?b, *c, d, x: e, ?y: f, **g) -> void")).yield_self do |type|
        assert_instance_of Types::Proc, type
        assert_equal "(a, ?b, *c, x: e, ?y: f, **g)", type.params.to_s
        assert_instance_of Types::Void, type.return_type
      end

      factory.type(RBS::Types::Variable.new(name: :T, location: nil)) do |type|
        assert_instance_of Types::Var, type
        assert_equal :T, type.name
      end
    end
  end

  def test_type_1
    with_factory() do |factory|
      parse_type("void").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("class").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("instance").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("self").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("top").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("bot").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("bool").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("nil").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("A", variables: [:A]).yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("singleton(::Object)").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("Array[Object]").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("_Each[self, void]").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("Super::duper").yield_self do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      factory.type(parse_type("Integer | nil")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end

      factory.type(parse_type("Integer & nil")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end

      factory.type(parse_type("30")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end

      factory.type(parse_type("[Integer, String]")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end

      factory.type(parse_type("{ foo: bar }")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end

      factory.type(parse_type("^(a, ?b, *c, d, x: e, ?y: f, **g) -> void")).yield_self do |type|
        assert_equal type, factory.type(factory.type_1(type))
      end
    end
  end

  def test_method_type
    with_factory() do |factory|
      self_type = factory.type(parse_type("::Array[X]", variables: [:X]))

      factory.method_type(parse_method_type("[A] (A) { (A, B) -> nil } -> void"), self_type: self_type).yield_self do |type|
        assert_equal "[A] (A) { (A, B) -> nil } -> void", type.to_s
      end

      factory.method_type(parse_method_type("[A] (A) -> void"), self_type: self_type).yield_self do |type|
        assert_equal "[A] (A) -> void", type.to_s
      end

      factory.method_type(parse_method_type("[A] () ?{ () -> A } -> void"), self_type: self_type).yield_self do |type|
        assert_equal "[A] () ?{ () -> A } -> void", type.to_s
      end

      factory.method_type(parse_method_type("[X] (X) -> void"), self_type: self_type).yield_self do |type|
        assert_match(/\[X\((\d+)\)\] \(X\(\1\)\) -> void/, type.to_s)
      end
    end
  end

  def test_method_type_1
    with_factory() do |factory|
      self_type = factory.type(parse_type("::Array[X]", variables: [:X]))

      parse_method_type("[A] (A) { (A, B) -> nil } -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, self_type: self_type),
                                     self_type: self_type)
        assert_equal original, type
      end

      parse_method_type("[A] (A) -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, self_type: self_type),
                                     self_type: self_type)
        assert_equal original, type
      end

      parse_method_type("[A] () ?{ () -> A } -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, self_type: self_type),
                                     self_type: self_type)
        assert_equal original, type
      end
    end
  end

  def test_interface_instance
    with_factory({ "foo.rbs" => <<FOO}) do |factory|
class Foo[A]
  def klass: -> class
  def get: -> A
  def set: (A) -> self
  private
  def hoge: -> instance
end
FOO
      factory.type(parse_type("::Foo[::String]")).yield_self do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_with interface.methods[:klass], "() -> singleton(::Foo)"
          assert_overload_with interface.methods[:get], "() -> ::String"
          assert_overload_with interface.methods[:set], "(::String) -> ::Foo[::String]"
          assert_overload_with interface.methods[:hoge], "() -> ::Foo[untyped]"
        end

        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_with interface.methods[:klass], "() -> singleton(::Foo)"
          assert_overload_with interface.methods[:get], "() -> ::String"
          assert_overload_with interface.methods[:set], "(::String) -> ::Foo[::String]"
          refute_operator interface.methods, :key?, :hoge
        end
      end
    end
  end

  def test_interface_interface
    with_factory({ "foo.rbs" => <<FOO }) do |factory|
interface _Each2[A, B]
  def each: () { (A) -> void } -> B
end
FOO
      factory.type(parse_type("::_Each2[::String, ::Array[::String]]")).yield_self do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_equal "{ () { (::String) -> void } -> ::Array[::String] }", interface.methods[:each].to_s
        end
      end
    end
  end

  def test_interface_class
    with_factory({ "foo.rbs" => <<FOO }) do |factory|
class People[X]
  def self.all: -> Array[People[::String]]
  def self.instance: -> instance
  def self.itself: -> self
end
FOO
      factory.type(parse_type("singleton(::People)")).yield_self do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_with interface.methods[:new], "[X] () -> ::People[X]"
          assert_overload_with interface.methods[:all], "() -> ::Array[::People[::String]]"
          assert_overload_with interface.methods[:instance], "() -> ::People[untyped]"
          assert_overload_with interface.methods[:itself], "() -> singleton(::People)"
        end
      end
    end
  end

  def test_interface_module
    with_factory({ "foo.rbs" => <<FOO }) do |factory|
module Subject[X]
  def self.foo: () -> void
  def bar: () -> X
end
FOO

      factory.type(parse_type("::Subject[bool]")).yield_self do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_with interface.methods[:bar], "() -> bool"
        end
      end

      factory.type(parse_type("singleton(::Subject)")).yield_self do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_with interface.methods[:foo], "() -> void"
          assert_overload_with interface.methods[:attr_reader], "(*(::String | ::Symbol)) -> ::NilClass"
        end
      end
    end
  end

  def test_literal_type
    with_factory() do |factory|
      factory.type(parse_type("3")).yield_self do |type|
        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          assert_overload_including interface.methods[:+], "(::Integer) -> ::Integer", "(::Float) -> ::Float"

          interface.methods[:yield_self].tap do |method|
            x = method.method_types[0].type_params[0]
            assert_includes method.to_s, " [#{x}] () { (3) -> #{x} } -> #{x} "
          end
        end
      end
    end
  end

  def test_tuple_type
    with_factory() do |factory|
      factory.type(parse_type("[::Integer, ::String]")).yield_self do |type|
        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          assert_overload_including interface.methods[:[]],
                                    "(0) -> ::Integer",
                                    "(1) -> ::String",
                                    "(::int) -> (::Integer | ::String)"

          assert_overload_including interface.methods[:[]=],
                                    "(0, ::Integer) -> ::Integer",
                                    "(1, ::String) -> ::String",
                                    "(::int, (::Integer | ::String)) -> (::Integer | ::String)"
        end
      end
    end
  end

  def test_record_type
    with_factory() do |factory|
      factory.type(parse_type("{ 1 => ::Integer, :foo => ::String, \"baz\" => bool }")).yield_self do |type|
        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          assert_overload_including interface.methods[:[]],
                                    "(1) -> ::Integer",
                                    "(:foo) -> ::String",
                                    "(\"baz\") -> bool"
          assert_overload_including interface.methods[:[]=],
                                    "(1, ::Integer) -> ::Integer",
                                    "(:foo, ::String) -> ::String",
                                    "(\"baz\", bool) -> bool"
        end
      end
    end
  end

  def test_union_type
    with_factory() do |factory|
      factory.type(parse_type("::Integer | ::String")).yield_self do |type|
        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          interface.methods[:to_s].yield_self do |entry|
            assert_overload_with entry, "() -> ::String"
          end

          interface.methods[:+].yield_self do |entry|
            assert_overload_including entry,
                                      "((::Integer & ::string)) -> (::Integer | ::String)",
                                      "((::Float & ::string)) -> (::Float | ::String)"
          end

          assert_nil interface.methods[:floor]
          assert_nil interface.methods[:end_with?]
        end
      end
    end
  end

  def test_union_type_methods
    with_factory({ "foo.rbs" => <<-RBS }) do |factory|
interface _I1
  def f: () -> void
  def g: () -> void

  def foo: (String) -> void
         | (Symbol) -> String
end

interface _I2
  def g: () -> void
  def h: () -> void

  def foo: () -> void
         | (Integer) -> Float
end
    RBS
      factory.type(parse_type("::_I1 | ::_I2")).tap do |type|
        factory.interface(type, private: false).tap do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          assert_equal Set[:g, :foo], Set.new(interface.methods.keys)
          assert_overload_with interface.methods[:g], "() -> void"
          assert_overload_with interface.methods[:foo],
                               "((::String & ::Integer)) -> (::Float | void)",
                               "((::Symbol & ::Integer)) -> (::Float | ::String)"
        end
      end
    end
  end

  def test_intersection_type
    with_factory({ "foo.rbs" => <<-RBS }) do |factory|
interface _I1
  def f: () -> void
  def g: () -> void
end

interface _I2
  def g: (String) -> Integer
  def h: () -> void
end
    RBS
      factory.type(parse_type("::_I1 & ::_I2")).tap do |type|
        factory.interface(type, private: false).tap do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          assert_equal Set[:f, :g, :h], Set.new(interface.methods.keys)
          assert_overload_with interface.methods[:f], "() -> void"
          assert_overload_with interface.methods[:g], "(::String) -> ::Integer"
          assert_overload_with interface.methods[:h], "() -> void"
        end
      end
    end
  end

  def test_proc_type
    with_factory() do |factory|
      factory.type(parse_type("^(String) -> Integer")).yield_self do |type|
        factory.interface(type, private: false).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          interface.methods[:call].yield_self do |entry|
            assert_overload_with entry, "(String) -> Integer"
          end

          interface.methods[:[]].yield_self do |entry|
            assert_overload_with entry, "(String) -> Integer"
          end
        end
      end
    end
  end

  def test_unfold
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
type name = ::String
type size = :S | :M | :L
    EOF

      factory.type(parse_type("::name")).tap do |type|
        unfolded = factory.unfold(type.name)

        assert_equal factory.type(parse_type("::String")), unfolded
      end

      factory.type(parse_type("::size")).tap do |type|
        unfolded = factory.unfold(type.name)

        assert_equal factory.type(parse_type(":S | :M | :L")), unfolded
      end
    end
  end

  def test_absolute_type
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
module Foo
end

class Foo::Bar
end

class Bar
end
    EOF

      factory.type(parse_type("Bar")).tap do |type|
        factory.absolute_type(type, namespace: RBS::Namespace.parse("::Foo")) do |absolute_type|
          assert_equal factory.type(parse_type("::Foo::Bar")), absolute_type
        end
      end

      factory.type(parse_type("Bar")).tap do |type|
        factory.absolute_type(type, namespace: RBS::Namespace.root) do |absolute_type|
          assert_equal factory.type(parse_type("::Bar")), absolute_type
        end
      end

      factory.type(parse_type("Baz")).tap do |type|
        factory.absolute_type(type, namespace: Namespace("::Foo")) do |absolute_type|
          assert_equal factory.type(parse_type("::Baz")), absolute_type
        end
      end
    end
  end

  def test_variable_rename
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
class Hello[X]
  def foo: [Y] (X, Y) -> void
end
    EOF

      factory.type(parse_type("::Hello[::Array[Y]]", variables: [:Y])).tap do |type|
        factory.interface(type, private: true).yield_self do |interface|
          assert_instance_of Steep::Interface::Interface, interface
          assert_equal type, interface.type

          method = interface.methods[:foo]
          assert_match(/\{ \[Y\(\d+\)\] \(::Array\[Y\], Y\(\d+\)\) -> void \}/, method.to_s)
        end
      end
    end
  end

  def test_expand_specials
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
class WithBuiltinMethods
end

class WithCustomMethods
  def is_a?: (Module) -> bool

  alias kind_of? is_a?

  def nil?: () -> bool

  def !: () -> bool
end
    EOF

      factory.type(parse_type("::WithBuiltinMethods")).tap do |type|
        factory.interface(type, private: true).tap do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          interface.methods[:is_a?].tap do |is_a|
            assert_instance_of Types::Logic::ReceiverIsArg, is_a.method_types[0].return_type
          end

          interface.methods[:kind_of?].tap do |kind_of|
            assert_instance_of Types::Logic::ReceiverIsArg, kind_of.method_types[0].return_type
          end

          interface.methods[:instance_of?].tap do |instance_of|
            assert_instance_of Types::Logic::ReceiverIsArg, instance_of.method_types[0].return_type
          end

          interface.methods[:nil?].tap do |nilp|
            assert_instance_of Types::Logic::ReceiverIsNil, nilp.method_types[0].return_type
          end

          interface.methods[:!].tap do |unot|
            assert_instance_of Types::Logic::Not, unot.method_types[0].return_type
          end
        end
      end

      factory.type(parse_type("::WithCustomMethods")).tap do |type|
        factory.interface(type, private: true).tap do |interface|
          assert_instance_of Steep::Interface::Interface, interface

          interface.methods[:is_a?].tap do |is_a|
            assert_instance_of Types::Boolean, is_a.method_types[0].return_type
          end

          interface.methods[:kind_of?].tap do |kind_of|
            assert_instance_of Types::Boolean, kind_of.method_types[0].return_type
          end

          interface.methods[:nil?].tap do |nilp|
            assert_instance_of Types::Boolean, nilp.method_types[0].return_type
          end

          interface.methods[:!].tap do |unot|
            assert_instance_of Types::Boolean, unot.method_types[0].return_type
          end
        end
      end
    end
  end
end
