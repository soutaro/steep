require_relative "test_helper"

class ConstraintsTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  BUILTIN = <<-EOB
class BasicObject
end

class Object < BasicObject
  def class: () -> class
end

class Class
  def new: (*any) -> any
end

class Module
end

class String
  def to_str: -> String
  def self.try_convert: (any) -> String
end

class Integer
  def to_int: -> Integer
  def self.sqrt: (Integer) -> Integer
end

class Array[A]
  def []: (Integer) -> A
  def []=: (Integer, A) -> A
end
  EOB

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
      assert_equal AST::Types::Intersection.build(types: [string, integer]), constraints.lower_bound(:b)
      assert_equal AST::Types::Union.build(types: [string, integer]), constraints.upper_bound(:b)
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

      subst = constraints.solution(checker, variance: variance, variables: Set.new([:a, :b, :c]))

      assert_equal string, subst[:a]
      assert_equal integer, subst[:b]
      assert_equal object, subst[:c]
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

      subst = constraints.solution(checker, variance: variance, variables: Set.new([:a, :b]))

      assert_equal string, subst[:a]
      assert_equal integer, subst[:b]
      refute_operator subst, :key?, :c
    end
  end

  def test_variable_elimination
    constraints = Subtyping::Constraints.new(unknowns: [])
    constraints.add_var(:a, :b)

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
    assert_equal AST::Types::Name::Instance.new(name: Names::Module.parse("::String"), args: [AST::Types::Any.new]),
                 constraints.eliminate_variable(AST::Types::Name::Instance.new(name: Names::Module.parse("::String"),
                                                                               args: [AST::Types::Var.new(name: :a)]),
                                                to: AST::Types::Top.new)
  end
end
