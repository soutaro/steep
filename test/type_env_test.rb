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
      assert_equal parse_type("::String | ::Integer"), env[node1]
    end
  end

  def test_join_local_vars_assignments
    with_factory do
      env = TypeEnv.new(constant_env)
      env = env.assign_local_variable(:a, parse_type("::Integer | ::Symbol | nil"), nil)

      env1 =
        env.assign_local_variable(:a, parse_type("::Integer"), nil)
          .assign_local_variable(:b, parse_type("::String"), nil)

      env2 =
        env.assign_local_variable(:a, parse_type("nil"), nil)
          .assign_local_variable(:c, parse_type("bool"), nil)

      env_ = env.join(env1, env2)

      assert_equal parse_type("::Integer | nil"), env_[:a]
      assert_equal parse_type("::String | nil"), env_[:b]
      assert_equal parse_type("bool | nil"), env_[:c]
    end
  end

  def test_join_local_vars_enforced
    with_factory do
      # # @type var a: Integer | Symbol | nil
      # a = ...
      #
      # if ...
      #   # @type var b: String?
      #   a = 123
      #   b = "foo"
      # else
      #   # @type var c: bool | Symbol
      #   a = nil
      #   c = true
      # end
      #
      env = TypeEnv.new(constant_env)
      env = env.assign_local_variable(:a, parse_type("::Integer | ::Symbol | nil"), parse_type("::Integer | ::Symbol | nil"))

      env1 =
        env.assign_local_variables({ a: parse_type("::Integer") })
          .assign_local_variable(:b, parse_type("::String"), parse_type("::String | nil"))

      env2 =
        env.assign_local_variables({ a: parse_type("nil") })
          .assign_local_variable(:c, parse_type("bool"), parse_type("bool | ::Symbol"))

      env_ = env.join(env1, env2)

      assert_equal parse_type("::Integer | nil"), env_[:a]
      assert_equal parse_type("::String | nil"), env_[:b]
      assert_equal parse_type("bool | ::Symbol | nil"), env_[:c]

      assert_equal parse_type("::Integer | ::Symbol | nil"), env_.enforced_type(:a)
      assert_nil env_.enforced_type(:b)
      assert_nil env_.enforced_type(:c)
    end
  end

  def test_join_calls_invalidate
    with_factory do
      # a = [1, nil].sample(2)
      # b = [:foo, nil].sample(2)
      #
      # if a[0] && b[1]
      #   if ...
      #     a = ["foo"]
      #   end
      #
      #   a[0]     # Integer | nil is expected here
      #   b[1]     # Symbol is expected here
      # end
      #

      node1 = parse_ruby("a = nil; a[0]").node.children[1]
      call1 = MethodCall::Typed.new(
        node: node1,
        context: MethodCall::TopLevelContext.new,
        method_name: MethodName("::Array#[]"),
        receiver_type: parse_type("::Array[::Integer | nil]"),
        actual_method_type: parse_method_type("(::Integer) -> ::Integer?"),
        method_decls: [],
        return_type: parse_type("::Integer | nil")
      )
      node2 = parse_ruby("b = nil; b[0]").node.children[1]
      call2 = MethodCall::Typed.new(
        node: node2,
        context: MethodCall::TopLevelContext.new,
        method_name: MethodName("::Array#[]"),
        receiver_type: parse_type("::Array[::Symbol | nil]"),
        actual_method_type: parse_method_type("(::Integer) -> ::Symbol?"),
        method_decls: [],
        return_type: parse_type("::Symbol | nil")
      )

      env = TypeEnv.new(constant_env)
      env =
        env.assign_local_variables({ a: parse_type("::Array[::Integer | nil]"), b: parse_type("::Array[::Symbol | nil]") })
          .add_pure_call(node1, call1, parse_type("::Integer"))
          .add_pure_call(node2, call2, parse_type("::Symbol"))

      env1 =
        env.assign_local_variables({ a: parse_type("::Array[::String]") })

      env_ = env.join(env, env1)

      assert_equal parse_type("::Array[::String] | ::Array[::Integer | nil]"), env_[:a]
      assert_equal parse_type("::Integer | nil"), env_[node1]
      assert_equal parse_type("::Symbol"), env_[node2]
    end
  end

  def test_refinements_branches_0
    with_factory do
      # array = ["string", 123, nil].shuffle
      # case x = array[0]
      # when String, Integer
      #   # x: String | Integer
      #   # array[0]: String | Integer
      # else
      #   # x: nil
      #   # array[0]: nil
      # end

      node = parse_ruby("a = nil; array[0]").node.children[1]
      call = MethodCall::Typed.new(
        node: node,
        context: MethodCall::TopLevelContext.new,
        method_name: MethodName("::Array#[]"),
        receiver_type: parse_type("::Array[::String?]"),
        actual_method_type: parse_method_type("(::Integer) -> ::String?"),
        method_decls: [],
        return_type: parse_type("::String?")
      )

      env = TypeEnv.new(constant_env)

      # array = ["string", nil].shuffle
      env =
        env.assign_local_variables({ array: parse_type("::Array[::String | ::Integer | nil]") })
          .add_pure_call(node, call, nil)

      # Truthy branch by `String === x`
      env1_t =
        env.refine_types(
          local_variable_types: { x: parse_type("::String") },
          pure_call_types: { node => parse_type("::String") }
        )

      # Falsy branch by `String === x`
      env1_f =
        env.refine_types(
          local_variable_types: { x: parse_type("::Integer?") },
          pure_call_types: { node => parse_type("::Integer?") }
        )

      # Truthy branch by `Integer === x`
      env2_t =
        env1_f.refine_types(
          local_variable_types: { x: parse_type("::Integer") },
          pure_call_types: { node => parse_type("::Integer") }
        )

      # Falsy branch by `Integer === x`
      env2_f =
        env1_f.refine_types(
          local_variable_types: { x: parse_type("nil") },
          pure_call_types: { node => parse_type("nil") }
        )

      # Body of `when String, Integer`
      env_body = env.join(env1_t, env2_t)

      # Body of `else`
      env_else = env2_f

      # After case-when
      env_after = env.join(env_body, env_else)

      assert_equal parse_type("::String | ::Integer"), env_body[:x]
      assert_equal parse_type("::String | ::Integer"), env_body[node]

      assert_equal parse_type("nil"), env_else[:x]
      assert_equal parse_type("nil"), env_else[node]

      assert_equal parse_type("::String | ::Integer | nil"), env_after[:x]
      assert_equal parse_type("::String | ::Integer | nil"), env_after[node]
    end
  end
end
