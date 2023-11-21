require_relative "test_helper"

class DocumentSymbolProviderTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep
  DocumentSymbolProvider = Services::DocumentSymbolProvider
  ContentChange = Services::ContentChange

  def dirs
    @dirs ||= []
  end

  def typecheck_service(steepfile: <<RUBY)
target :lib do
  check "hello.rb"
  signature "hello.rbs"
end
RUBY
    project = Project.new(steepfile_path: current_dir + "Steepfile")
    Project::DSL.parse(project, steepfile)

    Services::TypeCheckService.new(project: project)
  end

  def test_class_declaration
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class FooBar
  @a: Integer
  @@a: Integer
  def f: (foo) -> void
  attr_reader a: Integer
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      provider = DocumentSymbolProvider.new(service: service)

      provider.content_for(path: Pathname("hello.rbs")).tap do |content|
        assert_instance_of Array, content
        assert_equal 1, content.size
        assert_instance_of LanguageServer::Protocol::Interface::DocumentSymbol, content[0]
        assert_equal "FooBar", content[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::CLASS, content[0].kind
        assert_equal 4, content[0].children.size
        assert_equal "@a", content[0].children[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::PROPERTY, content[0].children[0].kind
        assert_equal "@@a", content[0].children[1].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::PROPERTY, content[0].children[1].kind
        assert_equal "f", content[0].children[2].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::METHOD, content[0].children[2].kind
        assert_equal "a", content[0].children[3].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::METHOD, content[0].children[3].kind
      end
    end
  end

  def test_module_declaration
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
module FooBar
  A: Integer
  type foo = Integer | String
  alias new_id id
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      provider = DocumentSymbolProvider.new(service: service)

      provider.content_for(path: Pathname("hello.rbs")).tap do |content|
        assert_instance_of Array, content
        assert_equal 1, content.size
        assert_instance_of LanguageServer::Protocol::Interface::DocumentSymbol, content[0]
        assert_equal "FooBar", content[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::MODULE, content[0].kind
        assert_equal 3, content[0].children.size
        assert_equal "A", content[0].children[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::CONSTANT, content[0].children[0].kind
        assert_equal "foo", content[0].children[1].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::CLASS, content[0].children[1].kind
        assert_equal "alias(new_id, id)", content[0].children[2].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::METHOD, content[0].children[2].kind
      end
    end
  end

  def test_interface_declaration
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
interface _FooBar
  def f: (foo) -> void
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      provider = DocumentSymbolProvider.new(service: service)

      provider.content_for(path: Pathname("hello.rbs")).tap do |content|
        assert_instance_of Array, content
        assert_equal 1, content.size
        assert_instance_of LanguageServer::Protocol::Interface::DocumentSymbol, content[0]
        assert_equal "_FooBar", content[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::INTERFACE, content[0].kind
        assert_equal 1, content[0].children.size
        assert_equal "f", content[0].children[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::METHOD, content[0].children[0].kind
      end
    end
  end

  def test_global_variable_declaration
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
$global: Integer
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      provider = DocumentSymbolProvider.new(service: service)

      provider.content_for(path: Pathname("hello.rbs")).tap do |content|
        assert_instance_of Array, content
        assert_equal 1, content.size
        assert_instance_of LanguageServer::Protocol::Interface::DocumentSymbol, content[0]
        assert_equal "$global", content[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::VARIABLE, content[0].kind
      end
    end
  end

  def test_module_include_extend_prepend
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class FooBar
  include Comparable
  extend Comparable
  prepend Comparable
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      provider = DocumentSymbolProvider.new(service: service)

      provider.content_for(path: Pathname("hello.rbs")).tap do |content|
        assert_instance_of Array, content
        assert_equal 1, content.size
        assert_instance_of LanguageServer::Protocol::Interface::DocumentSymbol, content[0]
        assert_equal 3, content[0].children.size
        assert_equal "include(::Comparable)", content[0].children[0].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::MODULE, content[0].children[0].kind
        assert_equal "extend(::Comparable)", content[0].children[1].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::MODULE, content[0].children[1].kind
        assert_equal "prepend(::Comparable)", content[0].children[2].name
        assert_equal LanguageServer::Protocol::Constant::SymbolKind::MODULE, content[0].children[2].kind
      end
    end
  end
end
