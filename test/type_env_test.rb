require_relative "test_helper"

class TypeEnvTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  ConstantEnv = TypeInference::ConstantEnv
  TypeEnv = TypeInference::TypeEnv

  def constant_env(context: nil)
    ConstantEnv.new(
      factory: factory,
      context: context,
      resolver: RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder)
    )
  end

  def test_local_variable
    with_factory do
      env = TypeEnv.new(constant_env)

      assignment = env.assignment(:x, parse_type("::String"))
      assert_equal [parse_type("::String"), nil], assignment

      env = env.merge(local_variable_types: { x: assignment })

      assert_equal parse_type("::String"), env[:x]
      assert_nil env.enforced_type(:x)
    end
  end

  def test_annotated_local_variable
    with_factory do
      env = TypeEnv.new(constant_env)

      assignment = env.assignment(:x, parse_type("::String"))
      env = env.merge(local_variable_types: { x: assignment })
      pin = env.pin_local_variables(nil)
      env = env.merge(local_variable_types: pin)

      assert_equal parse_type("::String"), env[:x]
      assert_equal parse_type("::String"), env.enforced_type(:x)
    end
  end
end
