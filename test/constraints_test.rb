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
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a])
    constraints.add(:a, sub_type: AST::Types::Name.new_instance(name: :String))
    constraints.add(:a, super_type: AST::Types::Name.new_instance(name: :Integer))

    assert_equal [AST::Types::Name.new_instance(name: :String)], constraints.lower_bound(:a)
    assert_equal [AST::Types::Name.new_instance(name: :Integer)], constraints.upper_bound(:a)
  end

  def test_subst
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a, :b])
    constraints.add(:a, sub_type: AST::Types::Name.new_instance(name: :String))
    constraints.add(:b, sub_type: AST::Types::Var.new(name: :a))

    subst = constraints.subst(checker)

    assert_equal AST::Types::Name.new_instance(name: :String), subst[:a]
    assert_equal AST::Types::Name.new_instance(name: :String), subst[:b]
  end

  def test_subst2
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a])
    constraints.add(:a, super_type: AST::Types::Name.new_instance(name: :String))

    subst = constraints.subst(checker)
    assert_equal AST::Types::Name.new_instance(name: :String), subst[:a]
  end

  def test_subst3
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a])
    constraints.add(:a,
                    super_type: AST::Types::Name.new_instance(name: :String),
                    sub_type: AST::Types::Name.new_instance(name: :Integer))

    assert_raises Subtyping::Constraints::UnsatisfiableConstraint do
      constraints.subst(checker)
    end
  end

  def test_subst4
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a])
    constraints.add(:a,
                    super_type: AST::Types::Name.new_instance(name: :String),
                    sub_type: AST::Types::Var.fresh(:x))

    assert_raises Subtyping::Constraints::UnsatisfiableConstraint do
      constraints.subst(checker)
    end
  end

  def test_subst5
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(domain: [:a])

    subst = constraints.subst(checker)
    refute_operator subst, :key?, :a
  end
end
