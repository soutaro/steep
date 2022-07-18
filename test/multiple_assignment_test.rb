require_relative "test_helper"

class MultipleAssignmentTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep

  MultipleAssignment = TypeInference::MultipleAssignment
  TypeEnv = TypeInference::TypeEnv
  ConstantEnv = TypeInference::ConstantEnv

  def node(type, *children)
    Parser::AST::Node.new(type, children)
  end

  def constant_env(context: nil)
    ConstantEnv.new(
      factory: factory,
      context: context,
      resolver: RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder)
    )
  end

  def test_tuple_assignment
    with_checker do
      source = parse_ruby("a, *b, c = _")
      mlhs, rhs = source.node.children

      masgn = MultipleAssignment.new()
      asgns = masgn.expand(mlhs, parse_type("[::Integer, ::String, ::Symbol]"), false)

      assert_equal(
        MultipleAssignment::Assignments.new(
          rhs_type: parse_type("[::Integer, ::String, ::Symbol]"),
          optional: false,
          leading_assignments: [[node(:lvasgn, :a), parse_type("::Integer")]],
          trailing_assignments: [[node(:lvasgn, :c), parse_type("::Symbol")]],
          splat_assignment: [node(:splat, node(:lvasgn, :b)), parse_type("[::String]")]
        ),
        asgns
      )
    end
  end

  def test_tuple_assignment_optional
    with_checker do
      source = parse_ruby("a, *b, c = _")
      mlhs, rhs = source.node.children

      masgn = MultipleAssignment.new()
      asgns = masgn.expand(mlhs, parse_type("[::Integer, ::String, ::Symbol]"), true)

      assert_equal(
        MultipleAssignment::Assignments.new(
          rhs_type: parse_type("[::Integer, ::String, ::Symbol]"),
          optional: true,
          leading_assignments: [[node(:lvasgn, :a), parse_type("::Integer")]],
          trailing_assignments: [[node(:lvasgn, :c), parse_type("::Symbol")]],
          splat_assignment: [node(:splat, node(:lvasgn, :b)), parse_type("[::String]")]
        ),
        asgns
      )
    end
  end

  def test_array_assignment
    with_checker do
      source = parse_ruby("a, *b, c = _")
      mlhs, rhs = source.node.children

      masgn = MultipleAssignment.new()
      asgns = masgn.expand(mlhs, parse_type("::Array[::Integer]"), false)

      assert_equal(
        MultipleAssignment::Assignments.new(
          rhs_type: parse_type("::Array[::Integer]"),
          optional: false,
          leading_assignments: [[node(:lvasgn, :a), parse_type("::Integer?")]],
          trailing_assignments: [[node(:lvasgn, :c), parse_type("::Integer?")]],
          splat_assignment: [node(:splat, node(:lvasgn, :b)), parse_type("::Array[::Integer]")]
        ),
        asgns
      )
    end
  end

  def test_array_assignment_optional
    with_checker do
      source = parse_ruby("a, *b, c = _")
      mlhs, rhs = source.node.children

      masgn = MultipleAssignment.new()
      asgns = masgn.expand(mlhs, parse_type("::Array[::Integer]"), true)

      assert_equal(
        MultipleAssignment::Assignments.new(
          rhs_type: parse_type("::Array[::Integer]"),
          optional: true,
          leading_assignments: [[node(:lvasgn, :a), parse_type("::Integer?")]],
          trailing_assignments: [[node(:lvasgn, :c), parse_type("::Integer?")]],
          splat_assignment: [node(:splat, node(:lvasgn, :b)), parse_type("::Array[::Integer]")]
        ),
        asgns
      )
    end
  end

  def test_hint_for_mlhs
    with_checker do
      env =

      masgn = MultipleAssignment.new()

      masgn.hint_for_mlhs(
        parse_ruby("a, b = _").node.children[0],
        TypeEnv.new(constant_env)
      ).tap do |hint|
        assert_equal parse_type("[untyped, untyped]"), hint
      end

      masgn.hint_for_mlhs(
        parse_ruby("a, b, *c = _").node.children[0],
        TypeEnv.new(constant_env)
      ).tap do |hint|
        assert_nil hint
      end

      masgn.hint_for_mlhs(
        parse_ruby("a, (b, c) = _").node.children[0],
        TypeEnv.new(constant_env)
      ).tap do |hint|
        assert_equal parse_type("[untyped, [untyped, untyped]]"), hint
      end

      masgn.hint_for_mlhs(
        parse_ruby("a, @b, $c = _").node.children[0],
        TypeEnv.new(constant_env)
          .assign_local_variables({ a: parse_type("::String") })
          .update(instance_variable_types: { :"@b" => parse_type("::Symbol") }, global_types: { :"$c" => parse_type("::Integer") })
      ).tap do |hint|
        assert_equal parse_type("[::String, ::Symbol, ::Integer]"), hint
      end
    end
  end
end
