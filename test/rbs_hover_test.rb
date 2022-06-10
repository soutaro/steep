require_relative "test_helper"

class RBSHoverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep
  HoverProvider = Services::HoverProvider
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

  def test_type_alias_type
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
type foo = Integer | String

class FooBar
  def f: (foo) -> void
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::RBS.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rbs"), line: 4, column: 11).tap do |content|
        assert_instance_of HoverProvider::RBS::TypeAliasContent, content
        assert_instance_of RBS::Location::WithChildren, content.location
        assert_equal "foo", content.location.source
      end
    end
  end

  def test_class_singleton_type
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class C
  def foo: () -> singleton(String)
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::RBS.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rbs"), line: 2, column: 28).tap do |content|
        assert_instance_of HoverProvider::RBS::ClassContent, content
        assert_instance_of RBS::Location, content.location
        assert_equal "String", content.location.source
        assert_instance_of RBS::AST::Declarations::Class, content.decl
      end
    end
  end

  def test_class_instance_type
    in_tmpdir do
      service = typecheck_service

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class Hoge end
class Qux
  @foo: Hoge
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::RBS.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rbs"), line: 3, column: 9).tap do |content|
        assert_instance_of HoverProvider::RBS::ClassContent, content
        assert_instance_of RBS::Location, content.location
        assert_equal "Hoge", content.location.source
        assert_instance_of RBS::AST::Declarations::Class, content.decl
      end
    end
  end

  def test_interface_type
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
interface _Fooable
  def foo: () -> nil
end

class Foo
  def foo: (_Fooable) -> singleton(String)
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::RBS.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rbs"), line: 6, column: 13).tap do |content|
        assert_instance_of HoverProvider::RBS::InterfaceContent, content
        assert_instance_of RBS::Location, content.location
        assert_equal "_Fooable", content.location.source
        assert_instance_of RBS::AST::Declarations::Interface, content.decl
      end
    end
  end

  def test_hover_comment_on_rbs
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
# Comment
class Foo
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::RBS.new(service: service)

      assert_nil hover.content_for(target: target, path: Pathname("hello.rbs"), line: 1, column: 4)
    end
  end
end
