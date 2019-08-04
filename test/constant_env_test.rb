require_relative "test_helper"

class ConstantEnvTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  Names = Steep::Names
  ConstantEnv = Steep::TypeInference::ConstantEnv

  BUILTIN = <<-EOS
class BasicObject
end

class Object < BasicObject
  def class: -> class
  def tap: { (instance) -> any } -> instance
end

class Class
end

class Module
  def block_given?: -> any
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
    sigs["builtin.rbi"] = BUILTIN

    with_factory(sigs, nostdlib: true) do |factory|
      env = ConstantEnv.new(factory: factory, context: context)
      yield env
    end
  end

  def test_from_toplevel
    with_constant_env(context: nil) do |env|
      assert_equal parse_type("singleton(::BasicObject)"),
                   env.lookup(Names::Module.parse("BasicObject"))
      assert_equal parse_type("singleton(::Kernel)"),
                   env.lookup(Names::Module.parse("Kernel"))
    end
  end

  def test_from_module
    with_constant_env("foo.rbi" => <<-EOS, context: Names::Module.parse("::A")) do |env|
module A end
module A::String end
    EOS
      assert_equal parse_type("singleton(::A::String)"),
                   env.lookup(Names::Module.parse("String"))
      assert_equal parse_type("singleton(::String)"),
                   env.lookup(Names::Module.parse("::String"))
    end
  end
end
