require_relative "test_helper"

class ConstantEnvTest < Minitest::Test
  include TestHelper

  Types = Steep::AST::Types
  Namespace = Steep::AST::Namespace
  Names = Steep::Names

  BUILTIN = <<-EOS
class BasicObject
end

class Object < BasicObject
  def class: -> module
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

  def constant_env(sigs = "", context:)
    signatures = Steep::AST::Signature::Env.new.tap do |env|
      parse_signature(BUILTIN).each do |sig|
        env.add sig
      end

      parse_signature(sigs).each do |sig|
        env.add sig
      end
    end

    builder = Steep::Interface::Builder.new(signatures: signatures)
    Steep::TypeInference::ConstantEnv.new(builder: builder, context: context)
  end

  def test_from_toplevel
    env = constant_env(context: nil)

    assert_equal Types::Name.new_class(name: "::BasicObject", constructor: true),
                 env.lookup(Names::Module.parse("BasicObject"))
    assert_equal Types::Name.new_module(name: "::Kernel"),
                 env.lookup(Names::Module.parse("Kernel"))
  end

  def test_from_module
    env = constant_env(<<EOS, context: Names::Module.parse("::A"))
module A
end

module A::String
end
EOS

    assert_equal Types::Name.new_module(name: "::A::String"),
                 env.lookup(Names::Module.parse("String"))
    assert_equal Types::Name.new_class(name: "::String", constructor: true),
                 env.lookup(Names::Module.parse("::String"))
    assert_equal Types::Name.new_module(name: "::Kernel"),
                 env.lookup(Names::Module.parse("Kernel"))
  end

  def test_nested_module
    env = constant_env(<<EOS, context: Names::Module.parse("::A"))
module A
end

module A::B
end

module A::B::C
end
EOS

    assert_equal Types::Name.new_module(name: "::A::B::C"),
                 env.lookup(Names::Module.parse("::A::B::C"))
    assert_equal Types::Name.new_module(name: "::A::B::C"),
                 env.lookup(Names::Module.parse("A::B::C"))
    assert_equal Types::Name.new_module(name: "::A::B::C"),
                 env.lookup(Names::Module.parse("B::C"))
  end

  def test_constant
    env = constant_env(<<EOS, context: Names::Module.parse("::A"))
module A
end

Foo: Integer
A::Foo: String
Bar: Symbol
EOS

    assert_equal Types::Name.new_instance(name: "::Integer"),
                 env.lookup(Names::Module.parse("::Foo"))
    assert_equal Types::Name.new_instance(name: "::String"),
                 env.lookup(Names::Module.parse("Foo"))
    assert_equal Types::Name.new_instance(name: "::Symbol"),
                 env.lookup(Names::Module.parse("Bar"))
    assert_nil env.lookup(Names::Module.parse("Baz"))
  end
end
