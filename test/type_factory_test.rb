require "test_helper"

class TypeFactoryTest < Minitest::Test
  def parse_type(str)
    Ruby::Signature::Parser.parse_type(str)
  end

  Types = Steep::AST::Types

  def with_factory
    env = Ruby::Signature::Environment.new()

    env_loader = Ruby::Signature::EnvironmentLoader.new(env: env)
    env_loader.load

    definition_builder = Ruby::Signature::DefinitionBuilder.new(env: env)

    yield Steep::AST::Types::Factory.new(builder: definition_builder)
  end

  def test_type
    with_factory do |factory|
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
        assert_instance_of Types::Name::Class, type
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

      factory.type(Ruby::Signature::Types::Variable.new(name: :T, location: nil)) do |type|
        assert_instance_of Types::Var, type
        assert_equal :T, type.name
      end
    end
  end
end
