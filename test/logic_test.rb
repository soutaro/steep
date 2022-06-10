require_relative "test_helper"

class LogicTest < Minitest::Test
  include TestHelper
  include TypeErrorAssertions
  include FactoryHelper
  include SubtypingHelper

  LocalVariableTypeEnv = Steep::TypeInference::LocalVariableTypeEnv
  Logic = Steep::TypeInference::Logic

  def test_result_vars
    with_checker do |checker|
      source = parse_ruby("x = 1; z = 3; x && (y = 3 or z)")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node, 2))

      assert_equal(Set[:x], t.vars)
      assert_equal(Set[], f.vars)
    end
  end

  def test_node_var
    with_checker do |checker|
      source = parse_ruby("x = 1; x")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node, 1))

      assert_equal(Set[].compare_by_identity.merge([dig(source.node, 1)]), t.nodes)
      assert_equal(Set[].compare_by_identity.merge([dig(source.node, 1)]), t.nodes)
    end
  end

  def test_node_lvasgn
    with_checker do |checker|
      source = parse_ruby("x = foo && bar")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node))

      assert_equal(Set[].compare_by_identity.merge(
        [
          dig(source.node),
          dig(source.node, 1),
          dig(source.node, 1, 0),
          dig(source.node, 1, 1)
        ]
      ), t.nodes)
      assert_equal(Set[].compare_by_identity.merge(
        [
          dig(source.node),
          dig(source.node, 1)
        ]
      ), f.nodes)
    end
  end

  def test_node_masgn
    with_checker do |checker|
      source = parse_ruby("x,y,*z = foo && bar")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node))

      assert_equal(Set[].compare_by_identity.merge(
        [
          dig(source.node),
          dig(source.node, 0),
          dig(source.node, 0, 0),
          dig(source.node, 0, 1),
          dig(source.node, 0, 2),
          dig(source.node, 0, 2, 0),
          dig(source.node, 1),
          dig(source.node, 1, 0),
          dig(source.node, 1, 1)
        ]
      ), t.nodes)
      assert_equal(Set[].compare_by_identity.merge(
        [
          dig(source.node),
          dig(source.node, 0),
          dig(source.node, 0, 0),
          dig(source.node, 0, 1),
          dig(source.node, 0, 2),
          dig(source.node, 0, 2, 0),
          dig(source.node, 1)
        ]
      ), f.nodes)
    end
  end

  def test_node_and
    with_checker do |checker|
      source = parse_ruby("x = 1; y = 1; z = 2; x && y && z")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node, 3))

      assert_equal(
        Set[].compare_by_identity.merge(
          [
            dig(source.node, 3),
            dig(source.node, 3, 0),
            dig(source.node, 3, 0, 0),
            dig(source.node, 3, 0, 1),
            dig(source.node, 3, 1)
          ]
        ),
        t.nodes
      )
      assert_equal(Set[].compare_by_identity.merge([dig(source.node, 3)]), f.nodes)
    end
  end

  def test_node_or
    with_checker do |checker|
      source = parse_ruby("x = 1; x = foo() or raise")
      logic = Logic.new(subtyping: checker)

      t, f = logic.nodes(node: dig(source.node, 1))

      assert_equal(
        Set[].compare_by_identity.merge([dig(source.node, 1)]),
        t.nodes
      )
      assert_equal(
        Set[].compare_by_identity.merge(
          [
            dig(source.node, 1),
            dig(source.node, 1, 0),
            dig(source.node, 1, 0, 1),
            dig(source.node, 1, 1),
          ]
        ),
        f.nodes
      )
    end
  end

  def test_environments
    with_checker do |checker|
      logic = Logic.new(subtyping: checker)

      env = LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )
        .assign(:x, type: parse_type("::Integer?"), node: nil)

      truthy, falsey = logic.environments(truthy_vars: Set[:x], falsey_vars: Set[:x], lvar_env: env)

      assert_equal parse_type("::Integer"), truthy[:x]
      assert_equal parse_type("nil"), falsey[:x]
    end
  end
end
