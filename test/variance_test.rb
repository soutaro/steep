require_relative "test_helper"

class VarianceTest < Minitest::Test
  include Steep
  include TestHelper
  include FactoryHelper

  VariableVariance = Subtyping::VariableVariance

  def parse_method_type(string, variables: [:A, :B, :C, :D, :E])
    type = RBS::Parser.parse_method_type(string, variables: variables)
    factory.method_type type, method_decls: Set[]
  end

  def parse_type(string, variables: [:A, :B, :C, :D, :E])
    type = RBS::Parser.parse_type(string, variables: variables)
    factory.type type
  end

  def test_type__base
    with_factory() do
      variance = VariableVariance.new(factory.env).add_type(parse_type("void"))
      assert_equal Set[], variance.covariants
      assert_equal Set[], variance.contravariants
    end
  end

  def test_type__union
    with_factory() do
      variance = VariableVariance.new(factory.env).add_type(parse_type("A | B"))
      assert_equal Set[:A, :B], variance.covariants
      assert_equal Set[], variance.contravariants
    end
  end

  def test_type__proc
    with_factory() do
      variance = VariableVariance.new(factory.env).add_type(parse_type("^(A, C) -> [B, C]"))
      assert_operator variance, :covariant?, :B
      assert_operator variance, :contravariant?, :A
      assert_operator variance, :invariant?, :C
      assert_operator variance, :unused?, :D
    end
  end

  def test_type__args_alias
    with_factory({ "a.rbs" => <<~RBS }) do
        type foo[out X, in Y, Z] = void
      RBS
      variance = VariableVariance.new(factory.env).add_type(parse_type("::foo[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C
    end
  end

  def test_type__args_class
    with_factory({ "a.rbs" => <<~RBS }) do
        class Foo[out X, in Y, Z]
        end

        class Bar = Foo
      RBS
      variance = VariableVariance.new(factory.env).add_type(parse_type("::Foo[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C

      variance = VariableVariance.new(factory.env).add_type(parse_type("::Bar[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C
    end
  end

  def test_type__args_module
    with_factory({ "a.rbs" => <<~RBS }) do
        module Foo[out X, in Y, Z]
        end

        module Bar = Foo
      RBS
      variance = VariableVariance.new(factory.env).add_type(parse_type("::Foo[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C

      variance = VariableVariance.new(factory.env).add_type(parse_type("::Bar[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C
    end
  end

  def test_type__args_interface
    with_factory({ "a.rbs" => <<~RBS }) do
        interface _Foo[out X, in Y, Z]
        end
      RBS
      variance = VariableVariance.new(factory.env).add_type(parse_type("::_Foo[A, B, C]"))
      assert_operator variance, :covariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :invariant?, :C
    end
  end

  def test_method_type__type
    with_factory() do
      variance = VariableVariance.new(factory.env).add_method_type(parse_method_type("(A, B) -> [A, C]"))
      assert_operator variance, :invariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :covariant?, :C
    end
  end

  def test_method_type__block
    with_factory() do
      variance = VariableVariance.new(factory.env).add_method_type(parse_method_type("() { (A, B) -> [A, C] } -> void"))
      assert_operator variance, :invariant?, :A
      assert_operator variance, :covariant?, :B
      assert_operator variance, :contravariant?, :C
    end
  end

  def test_method_type__self
    with_factory() do
      variance = VariableVariance.new(factory.env).add_method_type(parse_method_type("() { () [self: A] -> void } -> void"))
      assert_operator variance, :contravariant?, :A
    end
  end

  def test_method_type__generic
    with_factory() do
      variance = VariableVariance.new(factory.env).add_method_type(parse_method_type("[A, B, C] (A, B) -> [A, C]"))
      assert_operator variance, :invariant?, :A
      assert_operator variance, :contravariant?, :B
      assert_operator variance, :covariant?, :C
    end
  end
end
