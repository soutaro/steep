require_relative "test_helper"

class ConstraintsTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  def test_bounds
    with_factory do
      constraints = Subtyping::Constraints.new(unknowns: [:a, :b, :c])

      string = parse_type("::String")
      integer = parse_type("::Integer")

      constraints.add(:a, sub_type: string)
      constraints.add(:a, super_type: integer)

      constraints.add(:b, sub_type: string)
      constraints.add(:b, sub_type: integer)
      constraints.add(:b, super_type: integer)
      constraints.add(:b, super_type: string)

      assert_equal string, constraints.lower_bound(:a)
      assert_equal integer, constraints.upper_bound(:a)
      assert_equal parse_type("::String | ::Integer"),constraints.lower_bound(:b)
      assert_instance_of AST::Types::Intersection, constraints.upper_bound(:b)
      assert_equal AST::Types::Bot.new, constraints.lower_bound(:c)
      assert_equal AST::Types::Top.new, constraints.upper_bound(:c)
    end
  end

  def test_subst
    with_checker do |checker|
      object = parse_type("::Object")
      string = parse_type("::String")
      integer = parse_type("::Integer")

      constraints = Subtyping::Constraints.new(unknowns: [:a, :b, :c])
      constraints.add(:a, sub_type: string)
      constraints.add(:b, super_type: integer)
      constraints.add(:c, sub_type: object, super_type: object)

      variance = Subtyping::VariableVariance.new(
        covariants: Set.new([:a, :c]),
        contravariants: Set.new([:b, :c])
      )

      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_equal string, subst[:a]
      assert_equal integer, subst[:b]
      assert_equal object, subst[:c]
    end
  end

  def test_subst_with_generics_upper_bound
    with_checker(<<~RBS) do |checker|
        interface _Indexable[T]
          def []: (Integer) -> T
        end
      RBS
      constraints = Subtyping::Constraints.new(unknowns: [:X])
      constraints.add_generics_upper_bound(:X, parse_type("::_Indexable[::Integer]"))
      constraints.add(:X, super_type: parse_type("::Array[::Integer]"))

      variance = Subtyping::VariableVariance.new(covariants: Set[], contravariants: Set[])
      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_equal parse_type("::Array[::Integer]"), subst[:X]
    end
  end

  def test_subst2
    with_checker do |checker|
      object = AST::Builtin::Object.instance_type
      string = AST::Builtin::String.instance_type
      integer = AST::Builtin::Integer.instance_type

      constraints = Subtyping::Constraints.new(unknowns: [:a, :b, :c])
      constraints.add(:a, sub_type: string)
      constraints.add(:b, super_type: integer)
      constraints.add(:c, sub_type: object, super_type: object)

      variance = Subtyping::VariableVariance.new(
        covariants: Set.new([:a, :c]),
        contravariants: Set.new([:b, :c])
      )
      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_equal string, subst[:a]
      assert_equal integer, subst[:b]
      assert_equal object, subst[:c]
    end
  end

  def test_variable_elimination
    constraints = Subtyping::Constraints.new(unknowns: [:x])

    assert_equal AST::Types::Var.new(name: :x),
                 constraints.eliminate_variable(AST::Types::Var.new(name: :x), to: AST::Types::Top.new)
    assert_equal AST::Types::Top.new,
                 constraints.eliminate_variable(AST::Types::Var.new(name: :a), to: AST::Types::Top.new)
    assert_equal AST::Types::Bot.new,
                 constraints.eliminate_variable(AST::Types::Var.new(name: :a), to: AST::Types::Bot.new)
    assert_equal AST::Types::Any.new,
                 constraints.eliminate_variable(AST::Types::Var.new(name: :a), to: AST::Types::Any.new)

    assert_equal AST::Types::Any.new,
                 constraints.eliminate_variable(AST::Types::Union.build(types: [AST::Types::Var.new(name: :a),
                                                                                AST::Types::Var.new(name: :b)]),
                                                to: AST::Types::Top.new)
    assert_equal AST::Types::Any.new,
                 constraints.eliminate_variable(AST::Types::Intersection.build(types: [AST::Types::Var.new(name: :a),
                                                                                       AST::Types::Var.new(name: :b)]),
                                                to: AST::Types::Bot.new)
    assert_equal AST::Types::Name::Instance.new(name: TypeName("::String"), args: [AST::Types::Any.new]),
                 constraints.eliminate_variable(AST::Types::Name::Instance.new(name: TypeName("::String"),
                                                                               args: [AST::Types::Var.new(name: :a)]),
                                                to: AST::Types::Top.new)
  end

  def test_solve__with_nested_type_variable
    with_checker(<<~RBS) do |checker|
        interface _Indexable[T]
          def []: (Integer) -> T
        end
      RBS
      # { Array[Integer] <: A <: Array[B], B }
      constraints = Subtyping::Constraints.new(unknowns: [:A, :B])
      constraints.add(:A, sub_type: parse_type("::Array[::Integer]"), super_type: parse_type("::_Indexable[B]", variables: [:B]))

      variance = Subtyping::VariableVariance.new(covariants: Set[], contravariants: Set[])
      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_instance_of Interface::Substitution, subst

      assert_equal parse_type("::Array[::Integer]"), subst[:A]
      assert_equal parse_type("::Integer"), subst[:B]
    end
  end

  def test_solve__with_nested_type_variable__generics_upper_bound
    with_checker(<<~RBS) do |checker|
        interface _Indexable[T]
          def []: (Integer) -> T
        end
      RBS

      constraints = Subtyping::Constraints.new(unknowns: [:A, :B])
      constraints.add(:A, sub_type: parse_type("::Array[::Integer]"))
      constraints.add_generics_upper_bound(:A, parse_type("::_Indexable[B]", variables: [:B]))

      variance = Subtyping::VariableVariance.new(covariants: Set[], contravariants: Set[])
      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_instance_of Interface::Substitution, subst

      assert_equal parse_type("::Array[::Integer]"), subst[:A]
      assert_equal parse_type("::Integer"), subst[:B]
    end
  end

  def test_solve__fail_by_generics_upper_bound
    with_checker(<<~RBS) do |checker|
      RBS
      constraints = Subtyping::Constraints.new(unknowns: [:A, :B])
      constraints.add(:A, sub_type: parse_type("::String"))
      constraints.add_generics_upper_bound(:A, parse_type("::Integer"))

      variance = Subtyping::VariableVariance.new(covariants: Set[], contravariants: Set[])
      context = Subtyping::Constraints::Context.new(self_type: nil, instance_type: nil, class_type: nil, variance: variance)
      subst = Subtyping::Constraints.solve(constraints, checker, context)

      assert_instance_of Subtyping::Constraints::UnsatisfiableConstraint, subst
    end
  end
end
