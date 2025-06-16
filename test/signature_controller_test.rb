require_relative "test_helper"

class SignatureServiceTest < Minitest::Test
  include Steep
  include TestHelper

  SignatureService = Services::SignatureService
  ContentChange = Services::ContentChange

  def environment_loader
    @loader ||= RBS::EnvironmentLoader.new
  end

  def test_update
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class Hello
end
RBS
      ]
      service.update(changes)
    end

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello"))
    assert_operator service.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::Hello")
    assert_operator service.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::Object")

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class Hello
  def foo: () -> void
end
RBS
      ]
      service.update(changes)
    end

    refute_operator service.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::Hello")
    assert_operator service.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::Object")
  end

  def test_update_nested
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
module A
  class B
  end
end
RBS
      ]
      changes[Pathname("sig/bar.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
module A
  class C
  end
end

class X
end
RBS
      ]
      controller.update(changes)
    end

    controller.latest_builder.build_instance(RBS::TypeName.parse("::A"))
    controller.latest_builder.build_instance(RBS::TypeName.parse("::A::B"))
    controller.latest_builder.build_instance(RBS::TypeName.parse("::A::C"))
    controller.latest_builder.build_instance(RBS::TypeName.parse("::X"))

    assert_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A")
    assert_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A::B")
    assert_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A::C")
    assert_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::X")

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
module A
  class B
    def foo: () -> void
  end
end
RBS
      ]
      controller.update(changes)
    end

    refute_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A")
    refute_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A::B")
    refute_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::A::C")
    assert_operator controller.latest_builder.instance_cache, :key?, RBS::TypeName.parse("::X")
  end

  def test_update_syntax_error
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class Hello
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureService::SyntaxErrorStatus, controller.status
    assert_equal Set[Pathname("sig/foo.rbs")], controller.pending_changed_paths
    assert_equal 1, controller.status.diagnostics.size
    assert_instance_of Diagnostic::Signature::SyntaxError, controller.status.diagnostics[0]
  end

  def test_update_syntax_error2
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
@
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureService::SyntaxErrorStatus, controller.status
    assert_equal Set[Pathname("sig/foo.rbs")], controller.pending_changed_paths
    assert_equal 1, controller.status.diagnostics.size
    assert_instance_of Diagnostic::Signature::SyntaxError, controller.status.diagnostics[0]
  end

  def test_update_loading_error1
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class Hello
end

module Hello
end
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureService::AncestorErrorStatus, controller.status
    assert_equal 1, controller.status.diagnostics.size
    assert_instance_of Diagnostic::Signature::DuplicatedDeclaration, controller.status.diagnostics[0]
  end

  def test_update_loading_error2
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class World
  include UnknownTypeName
end
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureService::AncestorErrorStatus, controller.status
    assert_equal 1, controller.status.diagnostics.size
    assert_instance_of Diagnostic::Signature::UnknownTypeName, controller.status.diagnostics[0]
  end

  def test_update_after_syntax_error
    controller = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class A
end
RBS
      ]
      changes[Pathname("sig/bar.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class B
RBS
      ]

      controller.update(changes)
    end

    assert_instance_of SignatureService::SyntaxErrorStatus, controller.status
    assert_equal Set[Pathname("sig/foo.rbs"), Pathname("sig/bar.rbs")], controller.pending_changed_paths
    controller.files[Pathname("sig/foo.rbs")].tap do |file|
      assert_equal <<RBS, file.content
class A
end
RBS
      assert_instance_of RBS::AST::Declarations::Class, file.source.declarations[0]
    end

    {}.tap do |changes|
      changes[Pathname("sig/bar.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
class B
end
RBS
      ]

      controller.update(changes)
    end

    assert_operator controller.latest_env.class_decls, :key?, RBS::TypeName.parse("::B")
    assert_operator controller.latest_env.class_decls, :key?, RBS::TypeName.parse("::A")
  end

  def test_const_decls
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
VERSION: String
RBS
      ]
      service.update(changes)
    end

    service.const_decls(paths: Set[Pathname("sig/foo.rbs")], env: service.latest_env).tap do |consts|
      assert_equal Set[RBS::TypeName.parse("::VERSION")], Set.new(consts.each_key)
    end

    service.const_decls(paths: Set[RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "file.rbs"], env: service.latest_env).tap do |consts|
      assert_operator consts.each_key, :include?, RBS::TypeName.parse("::File::PATH_SEPARATOR")
    end
  end

  def test_global_decls
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        ContentChange.new(range: nil, text: <<RBS)
$VERSION: String
RBS
      ]
      service.update(changes)
    end

    service.global_decls(paths: Set[Pathname("sig/foo.rbs")]).tap do |consts|
      assert_equal Set[:$VERSION], Set.new(consts.each_key)
    end
  end

  def test__inline__update
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
end
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello")).tap do |definition|
      assert_instance_of RBS::Definition, definition
      assert_nil definition.methods[:foo]
    end

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
  def foo #: Integer
    123
  end
end
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello")).tap do |definition|
      assert_instance_of RBS::Definition, definition
      definition.methods[:foo].tap do |method|
        assert_instance_of RBS::Definition::Method, method
        assert_equal ["() -> ::Integer"], method.defs.map { _1.type.to_s }
      end
    end
  end

  def test__inline__update_syntax_error1
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
end
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello")).tap do |definition|
      assert_instance_of RBS::Definition, definition
      assert_nil definition.methods[:foo]
    end

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello")).tap do |definition|
      assert_instance_of RBS::Definition, definition
      assert_nil definition.methods[:foo]
    end
  end

  def test__inline__update_syntax_error2
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status

    service.latest_builder.build_instance(RBS::TypeName.parse("::Hello")).tap do |definition|
      assert_instance_of RBS::Definition, definition
      assert_nil definition.methods[:foo]
    end
  end

  def test__inline__update_empty_comment
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    assert_instance_of SignatureService::LoadedStatus, service.status

    {}.tap do |changes|
      changes[Pathname("lib/foo.rb")] = [
        ContentChange.new(range: nil, text: <<RUBY)
class Hello
  #
  def foo
  end
end
RUBY
      ]
      service.update(changes)
    end

    assert_instance_of SignatureService::LoadedStatus, service.status
  end
end
