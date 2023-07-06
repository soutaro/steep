require_relative "test_helper"

class TypeFactoryTest < Minitest::Test
  def parse_type(str, variables: [])
    RBS::Parser.parse_type(str, variables: variables)
  end

  def parse_method_type(str)
    RBS::Parser.parse_method_type(str)
  end

  def assert_overload_with(c, *types)
    types = types.map do |s|
      factory.method_type(parse_method_type(s), self_type: Steep::AST::Types::Self.new, subst2: nil, method_decls: Set[])
    end

    assert_equal Set.new(types), Set.new(c.method_types), "Expected: { #{types.join(" | ")} }, Actual: #{c.to_s}"
  end

  def assert_overload_including(c, *types)
    types = types.map do |s|
      factory.method_type(parse_method_type(s), self_type: Steep::AST::Types::Self.new, subst2: nil, method_decls: Set[])
    end

    assert_operator Set.new(types),
                    :subset?, Set.new(c.method_types),
                    "Expected: \n{ #{types.join(" | ")} }\n is a subset of \n{ #{c.method_types.join(" | ")} }"
  end

  Types = Steep::AST::Types
  Interface = Steep::Interface

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
        assert_equal "(a, ?b, *c, x: e, ?y: f, **g)", type.type.params.to_s
        assert_instance_of Types::Void, type.type.return_type
      end

      factory.type(parse_type("^() ?{ (Integer) -> void } -> void")).yield_self do |type|
        assert_instance_of Types::Proc, type

        assert_equal "()", type.type.params.to_s
        assert_instance_of Types::Void, type.type.return_type

        assert_instance_of Interface::Block, type.block
        assert_predicate type.block, :optional?
        assert_equal "?{ (Integer) -> void }", type.block.to_s
      end

      factory.type(RBS::Types::Variable.new(name: :T, location: nil)) do |type|
        assert_instance_of Types::Var, type
        assert_equal :T, type.name
      end
    end
  end

  def test_alias_type
    with_factory() do |factory|
      factory.type(parse_type("foo")).yield_self do |type|
        assert_instance_of Types::Name::Alias, type
        assert_equal TypeName("foo"), type.name
        assert_equal [], type.args
      end

      factory.type(parse_type("foo[untyped]")).yield_self do |type|
        assert_instance_of Types::Name::Alias, type
        assert_equal TypeName("foo"), type.name
        assert_equal [Types::Any.new], type.args
      end

      parse_type("foo").tap do |type|
        assert_equal type, factory.type_1(factory.type(type))
      end

      parse_type("foo[untyped]").tap do |type|
        assert_equal type, factory.type_1(factory.type(type))
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

      factory.method_type(parse_method_type("[A] (A) { (A, B) -> nil } -> void"), method_decls: Set[]).yield_self do |type|
        assert_equal "[A] (A) { (A, B) -> nil } -> void", type.to_s
      end

      factory.method_type(parse_method_type("[A] (A) -> void"), method_decls: Set[]).yield_self do |type|
        assert_equal "[A] (A) -> void", type.to_s
      end

      factory.method_type(parse_method_type("[A] () ?{ () -> A } -> void"), method_decls: Set[]).yield_self do |type|
        assert_equal "[A] () ?{ () -> A } -> void", type.to_s
      end

      factory.method_type(parse_method_type("[X] (X) -> void"), method_decls: Set[]).yield_self do |type|
        assert_method_type(
          "[X] (X) -> void",
          type
        )
      end
    end
  end

  def test_bounded_method_type
    with_factory() do |factory|
      self_type = factory.type(parse_type("::Array[X]", variables: [:X]))

      factory.method_type(parse_method_type("[A < Integer] (A) -> void"), method_decls: Set[]).yield_self do |type|
        assert_equal "[A < Integer] (A) -> void", type.to_s
      end

      factory.method_type(parse_method_type("[X < Integer] () -> X"), method_decls: Set[]).yield_self do |type|
        assert_method_type(
          "[X < Integer] () -> X",
          type
        )
      end

      factory.method_type(parse_method_type("[X < Integer, Y < Array[X]] (Y) -> X"), method_decls: Set[]).yield_self do |type|
        assert_method_type(
          "[X < Integer, Y < Array[X]] (Y) -> X",
          type
        )
      end
    end
  end

  def test_method_type_1
    with_factory() do |factory|
      self_type = factory.type(parse_type("::Array[X]", variables: [:X]))

      parse_method_type("[A] (A) { (A, B) -> nil } -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, method_decls: Set[]))
        assert_equal original, type
      end

      parse_method_type("[A] (A) -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, method_decls: Set[]))
        assert_equal original, type
      end

      parse_method_type("[A] () ?{ () -> A } -> void").tap do |original|
        type = factory.method_type_1(factory.method_type(original, method_decls: Set[]))
        assert_equal original, type
      end
    end
  end

  def test_unfold
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
type name = ::String
type size = :S | :M | :L
    EOF

      factory.type(parse_type("::name")).tap do |type|
        unfolded = factory.unfold(type.name, [])

        assert_equal factory.type(parse_type("::String")), unfolded
      end

      factory.type(parse_type("::size")).tap do |type|
        unfolded = factory.unfold(type.name, [])

        assert_equal factory.type(parse_type(":S | :M | :L")), unfolded
      end
    end
  end

  def test_expand_alias
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
type list[A] = nil | [A, list[A]]
    EOF

      factory.type(parse_type("::list[::String]")).tap do |type|
        assert_equal(
          factory.type(parse_type("nil | [::String, ::list[::String]]")),
          factory.expand_alias(type)
        )
      end
    end
  end

  def test_deep_expand_alias
    with_factory({ "foo.rbs" => <<-EOF }) do |factory|
type list[A] = nil | [A, list[A]]
    EOF

      factory.type(parse_type("::list[::String]")).tap do |type|
        assert_equal(
          factory.type(parse_type("nil | [::String, ::list[::String]]")),
          factory.deep_expand_alias(type)
        )
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
        factory.absolute_type(type, context: [nil, TypeName("::Foo")]) do |absolute_type|
          assert_equal factory.type(parse_type("::Foo::Bar")), absolute_type
        end
      end

      factory.type(parse_type("Bar")).tap do |type|
        factory.absolute_type(type, context: nil) do |absolute_type|
          assert_equal factory.type(parse_type("::Bar")), absolute_type
        end
      end

      factory.type(parse_type("Baz")).tap do |type|
        factory.absolute_type(type, context: [nil, ("::Foo")]) do |absolute_type|
          assert_equal factory.type(parse_type("::Baz")), absolute_type
        end
      end
    end
  end

  def test_partition_union__top
    with_factory() do |factory|
      factory.partition_union(factory.type(parse_type("top"))).tap do |truthy, falsy|
        assert_equal factory.type(parse_type("top")), truthy
        assert_equal factory.type(parse_type("top")), falsy
      end
    end
  end

  def test_partition_union__boolish
    with_factory() do |factory|
      factory.partition_union(factory.type(parse_type("::boolish"))).tap do |truthy, falsy|
        assert_equal factory.type(parse_type("top")), truthy
        assert_equal factory.type(parse_type("top")), falsy
      end
    end
  end

  def test_partition_union__bool_union
    with_factory() do |factory|
      factory.partition_union(factory.type(parse_type("bool | ::Symbol"))).tap do |truthy, falsy|
        assert_equal factory.type(parse_type("bool | ::Symbol")), truthy
        assert_equal factory.type(parse_type("bool")), falsy
      end
    end
  end
end
