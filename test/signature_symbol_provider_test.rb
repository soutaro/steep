require "test_helper"

class SignatureSymbolProviderTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  include Steep

  LSP = LanguageServer::Protocol
  SignatureSymbolProvider = Index::SignatureSymbolProvider
  RBSIndex = Index::RBSIndex

  def assignment
    Services::PathAssignment.all
  end

  def test_find_class_symbol
    with_factory({ "a.rbs" => <<RBS }) do |factory|
class Class1
  module Module1
    interface _Interface1
    end

    type alias1 = String
  end
end
RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new()
      provider.indexes << index

      assert_any! provider.query_symbol("", assignment: assignment) do |symbol|
        assert_equal 'Class1', symbol.name
        assert_equal "", symbol.container_name
        assert_equal LSP::Constant::SymbolKind::CLASS, symbol.kind
        assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
      end

      assert_any! provider.query_symbol("", assignment: assignment) do |symbol|
        assert_equal 'Module1', symbol.name
        assert_equal "Class1", symbol.container_name
        assert_equal LSP::Constant::SymbolKind::MODULE, symbol.kind
        assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
      end

      assert_any! provider.query_symbol("", assignment: assignment) do |symbol|
        assert_equal '_Interface1', symbol.name
        assert_equal "Class1::Module1", symbol.container_name
        assert_equal LSP::Constant::SymbolKind::INTERFACE, symbol.kind
        assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
      end

      assert_any! provider.query_symbol("", assignment: assignment) do |symbol|
        assert_equal 'alias1', symbol.name
        assert_equal "Class1::Module1", symbol.container_name
        assert_equal LSP::Constant::SymbolKind::ENUM, symbol.kind
        assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
      end

      assert_any! provider.query_symbol("class1", assignment: assignment) do |symbol|
        assert_equal 'Class1', symbol.name
      end

      assert_any! provider.query_symbol("class", assignment: assignment) do |symbol|
        assert_equal 'Class1', symbol.name
      end
    end
  end

  def test_find_method_symbol
    with_factory({ "a.rbs" => <<RBS }) do |factory|
class Class1
  def foo: () -> void

  def self.bar: () -> void
  def self.bar: () -> String | ...

  alias baz foo

  attr_accessor name: String
  attr_accessor self.email(@email2): String
end
RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new()
      provider.indexes << index

      provider.query_symbol("", assignment: assignment).tap do |symbols|
        assert_any! symbols do |symbol|
          assert_equal "#foo", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal ".bar", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
          assert_equal 4, symbol.location.start_line
        end

        assert_any! symbols do |symbol|
          assert_equal ".bar", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
          assert_equal 5, symbol.location.start_line
        end

        assert_any! symbols do |symbol|
          assert_equal "#baz", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal "#name", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal "#name=", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal ".email", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal ".email=", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal "@email2", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::FIELD, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end
      end
    end
  end

  def test_find_constant_global
    with_factory({ "a.rbs" => <<RBS }) do |factory|
module Steep
  VERSION: String
  $SteepError: IO
end
RBS
      env = factory.definition_builder.env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new()
      provider.indexes << index

      provider.query_symbol("", assignment: assignment).tap do |symbols|
        assert_any! symbols do |symbol|
          assert_equal "VERSION", symbol.name
          assert_equal "Steep", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::CONSTANT, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end

        assert_any! symbols do |symbol|
          assert_equal "$SteepError", symbol.name
          assert_nil symbol.container_name
          assert_equal LSP::Constant::SymbolKind::VARIABLE, symbol.kind
          assert_operator symbol.location.buffer.name, :end_with?, "a.rbs"
        end
      end
    end
  end
end
