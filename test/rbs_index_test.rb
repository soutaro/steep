require_relative "test_helper"

class RBSIndexTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  RBSIndex = Steep::Index::RBSIndex

  def test_class_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
module HelloWorld
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: TypeName("::HelloWorld")).count
    end
  end

  def test_method_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
class HelloWorld
  def f: () -> void

  def self.g: () -> void

  def self?.h: () -> void
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#f")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld.g")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#h")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld.h")).count
    end
  end

  def test_attribute_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
class HelloWorld
  attr_reader foo: Integer
  attr_writer bar: String
  attr_accessor baz: Symbol
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#foo")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#bar=")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#baz")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#baz=")).count
    end
  end

  def test_method_alias
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
class HelloWorld
  def self?.foo: () -> void

  alias bar foo
  alias self.baz self.foo
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld#bar")).count
      assert_equal 1, index.each_declaration(method_name: MethodName("::HelloWorld.baz")).count
    end
  end

  def test_interface_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
interface _HelloStr
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: TypeName("::_HelloStr")).count
    end
  end

  def test_alias_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
type num = Integer | Float | Rational
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: TypeName("::num")).count
    end
  end

  def test_const_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
Version: String
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(const_name: TypeName("::Version")).count
    end
  end
end
