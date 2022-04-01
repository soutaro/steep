require_relative "test_helper"

class ConstantEnvTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  ConstantEnv = Steep::TypeInference::ConstantEnv

  BUILTIN = <<-EOS
class BasicObject
end

class Object < BasicObject
  def class: -> class
  def tap: { (instance) -> untyped } -> instance
end

class Class
end

class Module
  def block_given?: -> untyped
end

class String
  def to_str: -> String
end

class Integer
  def to_int: -> Integer
end

class Symbol
end

module Kernel
end
  EOS


  def with_constant_env(sigs = {}, context:)
    sigs["builtin.rbs"] = BUILTIN

    with_factory(sigs, nostdlib: true) do |factory|
      env = ConstantEnv.new(factory: factory, context: context, resolver: RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder))
      yield env
    end
  end

  def test_from_module
    with_constant_env({ "foo.rbs" => <<-EOS }, context: [nil, TypeName("::A")]) do |env|
module A end
module A::String end
    EOS
      assert_equal TypeName("::A::String"), env.resolve(:String)[1]
      assert_equal TypeName("::String"), env.toplevel(:String)[1]
    end
  end
end
