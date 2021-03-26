require "test_helper"

class SignatureServiceTest < Minitest::Test
  include Steep
  include TestHelper

  SignatureService = Services::SignatureService
  ContentChange = Services::ContentChange

  def environment_loader
    @loader ||= RBS::EnvironmentLoader.new
  end

  def test_update
    service = SignatureService.load_from(environment_loader)

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

    service.latest_builder.build_instance(TypeName("::Hello"))
    assert_operator service.latest_builder.instance_cache, :key?, [TypeName("::Hello"), false]
    assert_operator service.latest_builder.instance_cache, :key?, [TypeName("::Object"), false]

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

    refute_operator service.latest_builder.instance_cache, :key?, [TypeName("::Hello"), false]
    assert_operator service.latest_builder.instance_cache, :key?, [TypeName("::Object"), false]
  end

  def test_update_nested
    controller = SignatureService.load_from(environment_loader)

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

    controller.latest_builder.build_instance(TypeName("::A"))
    controller.latest_builder.build_instance(TypeName("::A::B"))
    controller.latest_builder.build_instance(TypeName("::A::C"))
    controller.latest_builder.build_instance(TypeName("::X"))

    assert_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A"), false]
    assert_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A::B"), false]
    assert_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A::C"), false]
    assert_operator controller.latest_builder.instance_cache, :key?, [TypeName("::X"), false]

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

    refute_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A"), false]
    refute_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A::B"), false]
    refute_operator controller.latest_builder.instance_cache, :key?, [TypeName("::A::C"), false]
    assert_operator controller.latest_builder.instance_cache, :key?, [TypeName("::X"), false]
  end

  def test_update_syntax_error
    controller = SignatureService.load_from(environment_loader)

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
    controller = SignatureService.load_from(environment_loader)

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
    controller = SignatureService.load_from(environment_loader)

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
    controller = SignatureService.load_from(environment_loader)

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
    controller = SignatureService.load_from(environment_loader)

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
      assert_instance_of RBS::AST::Declarations::Class, file.decls[0]
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

    assert_operator controller.latest_env.class_decls, :key?, TypeName("::B")
    assert_operator controller.latest_env.class_decls, :key?, TypeName("::A")
  end

  def test_const_decls
    service = SignatureService.load_from(environment_loader)

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
      assert_equal Set[TypeName("::VERSION")], Set.new(consts.each_key)
    end

    service.const_decls(paths: Set[RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "file.rbs"], env: service.latest_env).tap do |consts|
      assert_operator consts.each_key, :include?, TypeName("::File::PATH_SEPARATOR")
    end
  end

  def test_global_decls
    service = SignatureService.load_from(environment_loader)

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
end
