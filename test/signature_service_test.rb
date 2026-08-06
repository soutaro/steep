require_relative "test_helper"

# Tests for SignatureService#last_changed_type_names: the type names whose
# definitions changed in the most recent #update, expanded over descendants,
# nested declarations and type aliases. Driven through TypeCheckService.
class SignatureServiceTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  TypeCheckService = Services::TypeCheckService

  def build_service(&block)
    project = Project.new(steepfile_path: Pathname.pwd + "Steepfile")
    Project::DSL.eval(project, &block)
    TypeCheckService.new(project: project)
  end

  # An alias that (transitively) references a changed type must enter the set,
  # even when declared in an unchanged file -- so a referencing file need only
  # record the alias name.
  def test_changed_names_includes_aliases_referencing_changed_type
    service = build_service do
      target :main do
        check "lib/a.rb"
        signature "sig/types.rbs"
        signature "sig/aliases.rbs"
      end
    end

    service.update(
      changes: {
        Pathname("sig/types.rbs") => [ContentChange.string(<<~RBS)],
          class Widget
            def size: () -> Integer
          end
        RBS
        # The alias lives in a separate file; transitively `gadget -> widget`.
        Pathname("sig/aliases.rbs") => [ContentChange.string(<<~RBS)],
          type widget = Widget
          type gadget = widget
        RBS
        Pathname("lib/a.rb") => [ContentChange.string("1\n")]
      }
    )

    # Change only the type in sig/types.rbs; sig/aliases.rbs is untouched.
    service.update(
      changes: {
        Pathname("sig/types.rbs") => [ContentChange.string(<<~RBS)]
          class Widget
            def size: () -> String
          end
        RBS
      }
    )

    changed_names = service.signature_services[:main].last_changed_type_names

    assert_includes changed_names, RBS::TypeName.parse("::Widget")
    # The alias that directly references Widget...
    assert_includes changed_names, RBS::TypeName.parse("::widget")
    # ...and the alias that transitively references it through another alias.
    assert_includes changed_names, RBS::TypeName.parse("::gadget")
  end

  # A change to a parent type must pull its descendants into the set, so a file
  # that mentions only a child is still re-checked.
  def test_changed_names_includes_descendants_of_changed_type
    service = build_service do
      target :main do
        check "lib/a.rb"
        signature "sig/types.rbs"
      end
    end

    service.update(
      changes: {
        Pathname("sig/types.rbs") => [ContentChange.string(<<~RBS)],
          class Animal
            def name: () -> Integer
          end

          class Dog < Animal
          end
        RBS
        Pathname("lib/a.rb") => [ContentChange.string("1\n")]
      }
    )

    # Change only the parent Animal; Dog's own declaration is untouched.
    service.update(
      changes: {
        Pathname("sig/types.rbs") => [ContentChange.string(<<~RBS)]
          class Animal
            def name: () -> String
          end

          class Dog < Animal
          end
        RBS
      }
    )

    changed_names = service.signature_services[:main].last_changed_type_names

    assert_includes changed_names, RBS::TypeName.parse("::Animal")
    # The descendant enters the set even though its own declaration is unchanged.
    assert_includes changed_names, RBS::TypeName.parse("::Dog")
  end

  # A change to an inline (`inline: true`) Ruby file's declared types must enter
  # the set so dependents are re-checked.
  def test_changed_names_includes_inline_declared_types
    service = build_service do
      target :lib do
        check "lib", inline: true
        signature "sig"
      end
    end

    hello_v1 = <<~RUBY
      class Hello
        # @rbs () -> Integer
        def world
          1
        end
      end
    RUBY
    hello_v2 = <<~RUBY
      class Hello
        # @rbs () -> String
        def world
          "x"
        end
      end
    RUBY

    service.update(changes: { Pathname("lib/hello.rb") => [ContentChange.string(hello_v1)] })

    # Change the inline-declared return type.
    service.update(changes: { Pathname("lib/hello.rb") => [ContentChange.string(hello_v2)] })

    changed_names = service.signature_services[:lib].last_changed_type_names
    assert_includes changed_names, RBS::TypeName.parse("::Hello"),
      "an inline-declared type change must enter changed_names"
  end
end
