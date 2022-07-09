require_relative "test_helper"

class TypeEnvTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  MethodCall = TypeInference::MethodCall
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

      env = env.assign_local_variables({ :x => parse_type("::String") })

      assert_equal parse_type("::String"), env[:x]
      assert_nil env.enforced_type(:x)
    end
  end

  def test_annotated_local_variable
    with_factory do
      env = TypeEnv.new(constant_env)

      env = env.assign_local_variable(:x, parse_type("::String"), nil)
      pin = env.pin_local_variables(nil)
      env = env.merge(local_variable_types: pin)

      assert_equal parse_type("::String"), env[:x]
      assert_equal parse_type("::String"), env.enforced_type(:x)
    end
  end

  def test_add_pure_node
    with_factory do
      env = TypeEnv.new(constant_env)

      node1 = parse_ruby("array[1].foo").node
      call1 = MethodCall::Typed.new(
        node: node1,
        context: MethodCall::TopLevelContext.new,
        method_name: MethodName("::Integer#foo"),
        receiver_type: parse_type("::Integer"),
        actual_method_type: parse_method_type("() -> (::String | ::Integer)"),
        method_decls: [],
        return_type: parse_type("::String | ::Integer")
      )

      node2 = parse_ruby("array[1]").node
      call2 = MethodCall::Typed.new(
        node: node1,
        context: MethodCall::TopLevelContext.new,
        method_name: MethodName("::Array#[]"),
        receiver_type: parse_type("::Array[::Integer]"),
        actual_method_type: parse_method_type("(::Integer) -> ::Integer"),
        method_decls: [],
        return_type: parse_type("::Integer")
      )

      env = env.add_pure_call(node1, call1, parse_type("::Integer"))
      assert_equal parse_type("::Integer"), env[node1]

      env = env.replace_pure_call_type(node1, parse_type("::String"))
      assert_equal parse_type("::String"), env[node1]

      env = env.add_pure_call(node2, call2, parse_type("::Integer"))

      assert_equal parse_type("::Integer"), env[node2]
      assert_nil env[node1]
    end
  end
end
