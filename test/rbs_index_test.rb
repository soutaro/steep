require_relative "test_helper"

class RBSIndexTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  RBSIndex = Steep::Index::RBSIndex

  # @rbs (String, ?path: Pathname) -> RBS::Source::Ruby
  def parse_inline_source(content, path: Pathname("a.rb"))
    buffer = RBS::Buffer.new(name: path, content: content)
    prism = Prism.parse(content, filepath: path.to_s)
    result = RBS::InlineParser.parse(buffer, prism)
    RBS::Source::Ruby.new(buffer, prism, result.declarations, result.diagnostics)
  end
  def test_class_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
module HelloWorld
end
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::HelloWorld")).count
    end
  end

  def test_class_alias_decl
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
module Foo = Kernel
    RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::Foo")).count
      assert_equal 1, index.each_reference(type_name: RBS::TypeName.parse("::Kernel")).count {|ref| ref.is_a?(RBS::AST::Declarations::ModuleAlias) }
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

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::_HelloStr")).count
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

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::num")).count
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

      assert_equal 1, index.each_declaration(const_name: RBS::TypeName.parse("::Version")).count
    end
  end

  def test_inline_class_decl
    with_factory() do |factory|
      source = parse_inline_source(<<~RUBY, path: Pathname("a.rbs"))
        class Person
        end
      RUBY

      env = factory.definition_builder.env

      env.add_source(source)

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::Person")).count
    end
  end

  def test_inline_module_decl
    with_factory() do |factory|
      env = factory.definition_builder.env

      source = parse_inline_source(<<~RUBY, path: Pathname("a.rbs"))
        module Person
        end
      RUBY

      env.add_source(source)

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::Person")).count
    end
  end

  def test_inline_method_def
    with_factory() do |factory|
      env = factory.definition_builder.env

      source = parse_inline_source(<<~RUBY, path: Pathname("a.rbs"))
        class Person
          def foo
          end
        end
      RUBY

      env.add_source(source)

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(method_name: MethodName("::Person#foo")).count
    end
  end

  def test_inline_nested_class_decl
    with_factory() do |factory|
      env = factory.definition_builder.env

      source = parse_inline_source(<<~RUBY, path: Pathname("a.rbs"))
        module Person
          class Address
          end
        end
      RUBY

      env.add_source(source)

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)

      builder.env(env)

      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::Person")).count
      assert_equal 1, index.each_declaration(type_name: RBS::TypeName.parse("::Person::Address")).count
    end
  end
end
