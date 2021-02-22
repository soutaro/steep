require "test_helper"

class SignatureControllerTest < Minitest::Test
  include Steep
  include TestHelper

  def environment_loader
    @loader ||= RBS::EnvironmentLoader.new
  end

  def test_update
    controller = SignatureController.load_from(environment_loader)

    assert_instance_of SignatureController::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
class Hello
end
RBS
      ]
      controller.update(changes)
    end

    controller.current_builder.build_instance(TypeName("::Hello"))
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::Hello"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::Object"), false]

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
class Hello
  def foo: () -> void
end
RBS
      ]
      controller.update(changes)
    end

    refute_operator controller.current_builder.instance_cache, :key?, [TypeName("::Hello"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::Object"), false]
  end

  def test_update_nested
    controller = SignatureController.load_from(environment_loader)

    assert_instance_of SignatureController::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
module A
  class B
  end
end
RBS
      ]
      changes[Pathname("sig/bar.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
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

    controller.current_builder.build_instance(TypeName("::A"))
    controller.current_builder.build_instance(TypeName("::A::B"))
    controller.current_builder.build_instance(TypeName("::A::C"))
    controller.current_builder.build_instance(TypeName("::X"))

    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::A"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::A::B"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::A::C"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::X"), false]

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
module A
  class B
    def foo: () -> void
  end
end
RBS
      ]
      controller.update(changes)
    end

    refute_operator controller.current_builder.instance_cache, :key?, [TypeName("::A"), false]
    refute_operator controller.current_builder.instance_cache, :key?, [TypeName("::A::B"), false]
    refute_operator controller.current_builder.instance_cache, :key?, [TypeName("::A::C"), false]
    assert_operator controller.current_builder.instance_cache, :key?, [TypeName("::X"), false]
  end

  def test_update_syntax_error
    controller = SignatureController.load_from(environment_loader)

    assert_instance_of SignatureController::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
class Hello
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureController::ErrorStatus, controller.status
    assert_equal 1, controller.status.errors.size
    assert_instance_of RBS::Parser::SyntaxError, controller.status.errors[0]
  end

  def test_update_loading_error
    controller = SignatureController.load_from(environment_loader)

    assert_instance_of SignatureController::LoadedStatus, controller.status

    {}.tap do |changes|
      changes[Pathname("sig/foo.rbs")] = [
        SignatureController::ContentChange.new(range: nil, text: <<RBS)
class Hello
end

module Hello
end
RBS
      ]
      controller.update(changes)
    end

    assert_instance_of SignatureController::ErrorStatus, controller.status
    assert_equal 1, controller.status.errors.size
    assert_instance_of RBS::DuplicatedDeclarationError, controller.status.errors[0]
  end
end
