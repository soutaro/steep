require_relative "test_helper"

class SignatureSymbolProviderTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include ShellHelper

  include Steep

  LSP = LanguageServer::Protocol
  SignatureSymbolProvider = Index::SignatureSymbolProvider
  RBSIndex = Index::RBSIndex

  def dirs
    @dirs ||= []
  end

  def assignment
    Services::PathAssignment.all
  end

  def test_find_class_symbol
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib/inline.rb", inline: true
          check "lib"
          signature "sig"
        end
      end

      target = project.targets[0] or raise

      service = Services::SignatureService.load_from(target.new_env_loader(), implicitly_returns_nil: true)
      service.update(
        {
          Pathname("sig/a.rbs") => [Services::ContentChange.string(<<RBS)],
class Class1
  module Module1
    interface _Interface1
    end

    type alias1 = String
  end
end
RBS
          Pathname("lib/inline.rb") => [Services::ContentChange.string(<<~RUBY)]
            class RubyClass
              module RubyModule
              end
            end
          RUBY
        }
      )

      env = service.latest_env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new(project: project, assignment: assignment)
      provider.indexes[project.targets[0]] = index

      provider.query_symbol("").tap do |symbols|
        symbols.find {|s| s.name == "Class1" }.tap do |symbol|
          assert_equal "", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::CLASS, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end
        symbols.find {|s| s.name == "RubyClass" }.tap do |symbol|
          assert_equal "", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::CLASS, symbol.kind
          assert_equal Pathname("lib/inline.rb"), symbol.location.buffer.name
        end
      end

      provider.query_symbol("").tap do |symbols|
        symbols.find {|s| s.name == "Module1" }.tap do |symbol|
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::MODULE, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end
        symbols.find {|s| s.name == "RubyModule" }.tap do |symbol|
          assert_equal "RubyClass", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::MODULE, symbol.kind
          assert_equal Pathname("lib/inline.rb"), symbol.location.buffer.name
        end
      end

      provider.query_symbol("").tap do |symbols|
        symbols.find {|s| s.name == "_Interface1" }.tap do |symbol|
          assert_equal "Class1::Module1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::INTERFACE, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end
      end

      provider.query_symbol("").tap do |symbols|
        symbols.find {|s| s.name == "alias1" }.tap do |symbol|
          assert_equal "Class1::Module1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::ENUM, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end
      end

      assert_any! provider.query_symbol("class1") do |symbol|
        assert_equal 'Class1', symbol.name
      end

      assert_any! provider.query_symbol("class") do |symbol|
        assert_equal 'Class1', symbol.name
      end
    end
  end

  def test_find_method_symbol
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib/inline.rb", inline: true
          check "lib"
          signature "sig"
        end
      end

      target = project.targets[0] or raise

      service = Services::SignatureService.load_from(target.new_env_loader(), implicitly_returns_nil: true)
      service.update(
        {
          Pathname("sig/a.rbs") => [Services::ContentChange.string(<<RBS)],
class Class1
  def foo: () -> void

  def self.bar: () -> void
  def self.bar: () -> String | ...

  alias baz foo

  attr_accessor name: String
  attr_accessor self.email(@email2): String
end
RBS
          Pathname("lib/inline.rb") => [Services::ContentChange.string(<<~RUBY)]
            class RubyClass
              def ruby_method #: void
              end
            end
          RUBY
        }
      )

      env = service.latest_env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new(assignment: assignment, project: project)
      provider.indexes[project.targets[0]] = index

      provider.query_symbol("").tap do |symbols|
        symbols = symbols.select {|s| s.container_name == "Class1" || s.container_name == "RubyClass" }

        assert_any! symbols do |symbol|
          assert_equal "#foo", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal ".bar", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
          assert_equal 4, symbol.location.start_line
        end

        assert_any! symbols do |symbol|
          assert_equal ".bar", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
          assert_equal 5, symbol.location.start_line
        end

        assert_any! symbols do |symbol|
          assert_equal "#baz", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal "#name", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal "#name=", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal ".email", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal ".email=", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::PROPERTY, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal "@email2", symbol.name
          assert_equal "Class1", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::FIELD, symbol.kind
          assert_equal Pathname("sig/a.rbs"), symbol.location.buffer.name
        end

        assert_any! symbols do |symbol|
          assert_equal "#ruby_method", symbol.name
          assert_equal "RubyClass", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::METHOD, symbol.kind
          assert_equal Pathname("lib/inline.rb"), symbol.location.buffer.name
        end
      end
    end
  end

  def test_find_constant_global
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      service = Services::SignatureService.load_from(project.targets[0].new_env_loader(), implicitly_returns_nil: true)
      service.update(
        {
          Pathname("sig/a.rbs") => [Services::ContentChange.string(<<RBS)]
module Steep
  DEFAULT_COMMAND: String
  $SteepError: IO
end
RBS
        }
      )

      env = service.latest_env

      index = RBSIndex.new()
      builder = RBSIndex::Builder.new(index: index)
      builder.env(env)

      provider = SignatureSymbolProvider.new(assignment: assignment, project: project)
      provider.indexes[project.targets[0]] = index

      provider.query_symbol("").tap do |symbols|
        symbols.find {|s| s.name == "DEFAULT_COMMAND" }.tap do |symbol|
          refute_nil symbol
          assert_equal "Steep", symbol.container_name
          assert_equal LSP::Constant::SymbolKind::CONSTANT, symbol.kind
          assert_equal Pathname("a.rbs"), symbol.location.buffer.name.basename
        end

        symbols.find {|s| s.name == "$SteepError" }.tap do |symbol|
          refute_nil symbol
          assert_nil symbol.container_name
          assert_equal LSP::Constant::SymbolKind::VARIABLE, symbol.kind
          assert_equal Pathname("a.rbs"), symbol.location.buffer.name.basename
        end
      end
    end
  end
end
