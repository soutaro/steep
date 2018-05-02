require_relative "test_helper"

class ConstraintsTest < Minitest::Test
  include TestHelper
  include Steep

  BUILTIN = <<-EOB
class BasicObject
end

class Object <: BasicObject
  def class: () -> class
end

class Class<'instance>
  def new: (*any, **any) -> 'instance
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

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
end
  EOB

  def new_checker(signature)
    env = AST::Signature::Env.new

    parse_signature(BUILTIN).each do |sig|
      env.add sig
    end

    parse_signature(signature).each do |sig|
      env.add sig
    end

    builder = Interface::Builder.new(signatures: env)
    Subtyping::Check.new(builder: builder)
  end

  def test_bounds
    constraints = Subtyping::Constraints.new(unknowns: [:a, :b, :c])

    string = AST::Types::Name.new_instance(name: :String)
    integer = AST::Types::Name.new_instance(name: :Integer)

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

  def test_subst
    checker = new_checker("")

    object = AST::Types::Name.new_instance(name: :Object)
    string = AST::Types::Name.new_instance(name: :String)
    integer = AST::Types::Name.new_instance(name: :Integer)

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

  def test_subst2
    checker = new_checker("")

    object = AST::Types::Name.new_instance(name: :Object)
    string = AST::Types::Name.new_instance(name: :String)
    integer = AST::Types::Name.new_instance(name: :Integer)

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
    assert_equal AST::Types::Name.new(name: "::String", args: [AST::Types::Any.new]),
                 constraints.eliminate_variable(AST::Types::Name.new(name: "::String", args: [AST::Types::Var.new(name: :a)]),
                                                to: AST::Types::Top.new)
  end
end
