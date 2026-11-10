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

  def test_update__resolve_again__name_in_outer_module
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/a.rbs" => <<~RBS, "sig/b.rbs" => <<~RBS)
      module M
        class A
          def foo: () -> B
        end
      end
    RBS
      class B
      end
    RBS
    assert_equal ["() -> ::B"], method_types(service, "::M::A", :foo)

    paths = update_files(service, "sig/m_b.rbs" => <<~RBS)
      module M
        class B
        end
      end
    RBS
    assert_equal Set[Pathname("sig/a.rbs")], paths
    assert_equal ["() -> ::M::B"], method_types(service, "::M::A", :foo)

    paths = update_files(service, "sig/m_b.rbs" => "")
    assert_equal Set[Pathname("sig/a.rbs")], paths
    assert_equal ["() -> ::B"], method_types(service, "::M::A", :foo)
  end

  def test_update__resolve_again__unresolved_name
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/a.rbs" => <<~RBS)
      class A
        def foo: () -> Foo
      end
    RBS
    assert_raises(RBS::NoTypeFoundError) { method_types(service, "::A", :foo) }

    update_files(service, "sig/foo.rbs" => <<~RBS)
      class Foo
      end
    RBS
    assert_equal ["() -> ::Foo"], method_types(service, "::A", :foo)

    update_files(service, "sig/foo.rbs" => "")
    assert_raises(RBS::NoTypeFoundError) { method_types(service, "::A", :foo) }
  end

  def test_update__resolve_again__alias
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/alias.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      module M
        class Foo = Bar
      end

      class Bar
      end
    RBS
      class A
        def foo: () -> M::Foo
      end
    RBS
    assert_equal ["() -> ::Bar"], method_types(service, "::A", :foo)

    # `M::Foo` is an alias of `M::Bar`, instead of `::Bar`
    update_files(service, "sig/m_bar.rbs" => <<~RBS)
      module M
        class Bar
        end
      end
    RBS
    assert_equal ["() -> ::M::Bar"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__alias_to_removed_class
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/alias.rbs" => <<~RBS, "sig/d.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      class Y = ::D
    RBS
      class D
      end
    RBS
      class A
        def foo: () -> Y
      end
    RBS
    assert_equal ["() -> ::D"], method_types(service, "::A", :foo)

    # The alias keeps the resolved name `::D`, but it cannot be resolved
    update_files(service, "sig/d.rbs" => "")
    assert_raises(RBS::NoTypeFoundError) { method_types(service, "::A", :foo) }

    update_files(service, "sig/d.rbs" => <<~RBS)
      class D
      end
    RBS
    assert_equal ["() -> ::D"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__alias_target_changed
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/alias.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      class Y = ::Integer
    RBS
      class A
        def foo: () -> Y
      end
    RBS
    assert_equal ["() -> ::Integer"], method_types(service, "::A", :foo)

    # The names exist in both environments, and the alias is a changed name
    paths = update_files(service, "sig/alias.rbs" => <<~RBS)
      class Y = ::String
    RBS
    assert_equal Set[Pathname("sig/a.rbs")], paths
    assert_equal ["() -> ::String"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__class_replaced_by_alias
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/x.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      class X
      end
    RBS
      class A
        def foo: () -> X
      end
    RBS
    assert_equal ["() -> ::X"], method_types(service, "::A", :foo)

    # The name exists in both environments, but the resolution goes through the alias
    paths = update_files(service, "sig/x.rbs" => <<~RBS)
      class X = ::Integer
    RBS
    assert_equal Set[Pathname("sig/a.rbs")], paths
    assert_equal ["() -> ::Integer"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__namespace_of_qualified_name
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/k.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      class K
        class D
        end
      end

      module P
      end
    RBS
      class A
        def foo: () -> P::C::D
      end
    RBS
    assert_raises(RBS::NoTypeFoundError) { method_types(service, "::A", :foo) }

    # Only the namespace of `P::C::D` is added
    update_files(service, "sig/p.rbs" => <<~RBS)
      module P
        class C = ::K
      end
    RBS
    assert_equal ["() -> ::K::D"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__use_wildcard
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/foo.rbs" => <<~RBS, "sig/a.rbs" => <<~RBS)
      module Foo
        class Baz
        end
      end
    RBS
      use Foo::*

      class A
        def foo: () -> Bar
      end
    RBS
    assert_raises(RBS::NoTypeFoundError) { method_types(service, "::A", :foo) }

    update_files(service, "sig/bar.rbs" => <<~RBS)
      module Foo
        class Bar
        end
      end
    RBS
    assert_equal ["() -> ::Foo::Bar"], method_types(service, "::A", :foo)
  end

  def test_update__resolve_again__same_name_in_same_context
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    # Both files resolve `B` in the same context, and the second one hits the cache of the resolver
    update_files(service, "sig/a1.rbs" => <<~RBS, "sig/a2.rbs" => <<~RBS, "sig/b.rbs" => <<~RBS)
      module M
        class A1
          def foo: () -> B
        end
      end
    RBS
      module M
        class A2
          def foo: () -> B
        end
      end
    RBS
      class B
      end
    RBS
    assert_equal ["() -> ::B"], method_types(service, "::M::A1", :foo)
    assert_equal ["() -> ::B"], method_types(service, "::M::A2", :foo)

    paths = update_files(service, "sig/m_b.rbs" => <<~RBS)
      module M
        class B
        end
      end
    RBS
    assert_equal Set[Pathname("sig/a1.rbs"), Pathname("sig/a2.rbs")], paths
    assert_equal ["() -> ::M::B"], method_types(service, "::M::A1", :foo)
    assert_equal ["() -> ::M::B"], method_types(service, "::M::A2", :foo)
  end

  def test_update__resolve_again__inline
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "lib/a.rb" => <<~RUBY, "sig/b.rbs" => <<~RBS)
      module M
        class A
          def foo #: B
            _ = nil
          end
        end
      end
    RUBY
      class B
      end
    RBS
    assert_equal ["() -> ::B"], method_types(service, "::M::A", :foo)

    update_files(service, "sig/m_b.rbs" => <<~RBS)
      module M
        class B
        end
      end
    RBS
    assert_equal ["() -> ::M::B"], method_types(service, "::M::A", :foo)
  end

  def test_update__resolve_again__library
    Dir.mktmpdir do |dir|
      (Pathname(dir) + "lib.rbs").write(<<~RBS)
        module Lib
          class A
            def foo: () -> B
          end
        end

        class B
        end
      RBS

      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(dir))
      service = SignatureService.load_from(loader, implicitly_returns_nil: true)
      assert_equal ["() -> ::B"], method_types(service, "::Lib::A", :foo)

      paths = update_files(service, "sig/lib.rbs" => <<~RBS)
        module Lib
          class B
          end
        end
      RBS
      # The buffer of a library file is named by its absolute path
      assert_equal Set[Pathname(dir) + "lib.rbs"], paths
      assert_equal ["() -> ::Lib::B"], method_types(service, "::Lib::A", :foo)
    end
  end

  def test_update__resolve_again__unaffected
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/a.rbs" => <<~RBS)
      module M
        class A
          def foo: () -> String
        end
      end
    RBS
    decl = service.latest_env.class_decls.fetch(RBS::TypeName.parse("::M::A")).primary_decl

    # `::N::String` is not tested while resolving `String` in `M::A`, and `::Integer` is not mentioned
    paths = update_files(service, "sig/b.rbs" => <<~RBS)
      module N
        class String
        end
      end

      class B
        def foo: () -> Integer
      end
    RBS
    assert_empty paths

    assert_same decl, service.latest_env.class_decls.fetch(RBS::TypeName.parse("::M::A")).primary_decl
  end

  def test_update__resolve_again__after_syntax_error
    service = SignatureService.load_from(environment_loader, implicitly_returns_nil: true)

    update_files(service, "sig/a.rbs" => <<~RBS, "sig/b.rbs" => <<~RBS)
      module M
        class A
          def foo: () -> B
        end
      end
    RBS
      class B
      end
    RBS

    # The environment keeps the one before the error, and the records with it
    service.update({ Pathname("sig/m_b.rbs") => [ContentChange.string("module M\n  class B\n")] })
    assert_instance_of SignatureService::SyntaxErrorStatus, service.status
    assert_equal ["() -> ::B"], method_types(service, "::M::A", :foo)

    paths = update_files(service, "sig/m_b.rbs" => <<~RBS)
      module M
        class B
        end
      end
    RBS
    assert_equal Set[Pathname("sig/a.rbs")], paths
    assert_equal ["() -> ::M::B"], method_types(service, "::M::A", :foo)
  end
end
