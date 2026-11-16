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

  def update_files(service, files)
    changes = files.to_h {|path, content| [Pathname(path), [ContentChange.string(content)]] }
    service.update(changes).tap do
      assert_instance_of SignatureService::LoadedStatus, service.status
    end
  end

  def method_types(service, type_name, method_name)
    definition = service.latest_builder.build_instance(RBS::TypeName.parse(type_name))
    definition.methods.fetch(method_name).defs.map { _1.type.to_s }
  end

  def decl_paths(service, type_name)
    entry = service.latest_env.class_decls.fetch(RBS::TypeName.parse(type_name))
    entry.each_decl.map { _1.location&.buffer&.name }
  end

  def test_update__keep_order
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/mods.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS, "sig/b.rbs" => <<~RBS)
      module MA
        def m: () -> Integer
      end

      module MB
        def m: () -> String
      end
    RBS
      class Foo
        include MA
      end
    RBS
      class Foo
        include MB
      end
    RBS
    assert_equal [Pathname("sig/a.rbs"), Pathname("sig/b.rbs")], decl_paths(service, "::Foo")
    assert_equal ["() -> ::String"], method_types(service, "::Foo", :m)

    update_files(service, "sig/a.rbs" => <<~RBS)
      class Foo
        include MA

        def foo: () -> void
      end
    RBS
    assert_equal [Pathname("sig/a.rbs"), Pathname("sig/b.rbs")], decl_paths(service, "::Foo")
    assert_equal ["() -> ::String"], method_types(service, "::Foo", :m)
  end

  def test_update__keep_order__error_at_updated_file
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/a.rbs" => <<~RBS, "sig/b.rbs" => <<~RBS)
      class A
      end
    RBS
      type t = Integer
    RBS

    # `sig/a.rbs` is before `sig/b.rbs`, but the error is reported at the updated file
    service.update({ Pathname("sig/a.rbs") => [ContentChange.string(<<~RBS)] })
      class A
      end

      type t = String
    RBS
    assert_instance_of SignatureService::AncestorErrorStatus, service.status
    assert_equal 1, service.status.diagnostics.size
    service.status.diagnostics[0].tap do |diagnostic|
      assert_instance_of Diagnostic::Signature::DuplicatedDeclaration, diagnostic
      assert_equal Pathname("sig/a.rbs"), diagnostic.location&.buffer&.name
    end
  end
end
