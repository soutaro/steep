require_relative "test_helper"

class TypeCheckServiceTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  TypeCheckService = Services::TypeCheckService

  def project
    @project ||= Project.new(steepfile_path: Pathname.pwd + "Steepfile").tap do |project|
      Project::DSL.eval(project) do
        target :core do
          check "lib/core.rb"
          signature "sig/core.rbs"
        end

        target :main do
          check "lib/main.rb"
          signature "sig/main.rbs"
        end

        target :inline do
          check "lib/inline.rb", inline: true
        end

        target :test do
          unreferenced!

          check "test/core_test.rb"
          signature "sig/core_test.rbs"
        end
      end
    end
  end

  def reset_changes
    {
      Pathname("lib/core.rb") => [ContentChange.string("")],
      Pathname("sig/core.rbs") => [ContentChange.string("")],
      Pathname("lib/main.rb") => [ContentChange.string("")],
      Pathname("sig/main.rbs") => [ContentChange.string("")],
      Pathname("lib/inline.rb") => [ContentChange.string("")],
      Pathname("test/core_test.rb") => [ContentChange.string("")],
      Pathname("sig/core_test.rbs") => [ContentChange.string("")],
    }
  end

  def test_update_file__signature
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("sig/main.rbs") => [ContentChange.string(<<RBS)],
class Customer
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.signature_services[:core].files, :key?, Pathname("sig/main.rbs")
      assert_operator service.signature_services[:main].files, :key?, Pathname("sig/main.rbs")
      assert_operator service.signature_services[:test].files, :key?, Pathname("sig/main.rbs")
    end
  end

  def test_update_file__signature_unreferenced
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("sig/core_test.rbs") => [ContentChange.string(<<RBS)],
class Customer
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      refute_operator service.signature_services[:core].files, :key?, Pathname("sig/core_test.rbs")
      refute_operator service.signature_services[:main].files, :key?, Pathname("sig/core_test.rbs")
      assert_operator service.signature_services[:test].files, :key?, Pathname("sig/core_test.rbs")
    end
  end

  def test_update_file__ruby
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/main.rb") => [ContentChange.string(<<RBS)],
class Customer
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/main.rb")
    end
  end

  def test_typecheck__ruby_syntax_error
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
class Account
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      service.source_files[Pathname("lib/core.rb")].tap do |file|
        assert_any!(file.errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::SyntaxError, error
          assert_equal 1, error.location.line
          assert_equal 13, error.location.column
          assert_equal 2, error.location.last_line
          assert_equal 0, error.location.last_column
        end
      end
    end
  end

  def test_typecheck__ruby_encoding_error
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    broken = "寿限無寿限無".encode(Encoding::EUC_JP)

    broken.force_encoding(Encoding::UTF_8)

    {
      Pathname("lib/core.rb") => [ContentChange.string(broken)]
    }.tap do |changes|
      service.update(changes: changes)
      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      service.source_files[Pathname("lib/core.rb")].tap do |file|
        assert_nil file.errors
        assert_equal "", file.content
      end
    end
  end

  def test_type_check__ruby_annotation_syntax_error
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
class Account
  # @type self: Array[
end
RUBY
    }.tap do |changes|
      service.update(changes: changes)
      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      service.source_files[Pathname("lib/core.rb")].tap do |file|
        assert_any!(file.errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::AnnotationSyntaxError, error
          assert_equal "Array[", error.location.source
          assert_equal "Syntax error caused by token `pEOF`", error.message
        end
      end
    end
  end

  def test_typecheck__ruby_errors
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class Core
end
RBS
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
class Core
end
RUBY
      Pathname("lib/main.rb") => [ContentChange.string(<<RUBY)],
1+""
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })
      service.typecheck_source(path: Pathname("lib/main.rb"), target: project.targets.find { _1.name == :main })

      assert_equal [], service.diagnostics.dig(Pathname("lib/core.rb"))

      service.diagnostics[Pathname("lib/main.rb")].tap do |errors|
        assert_equal 1, errors.size
        assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, errors[0]
      end
    end
  end

  def test_typecheck__ruby_project_class
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class Core
end
RBS
      Pathname("sig/main.rbs") => [ContentChange.string(<<RBS)],
class Main
end
RBS
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
Core.new
Main.new
RUBY
      Pathname("lib/main.rb") => [ContentChange.string(<<RUBY)],
Core.new
Main.new
RUBY
      Pathname("test/core_test.rb") => [ContentChange.string(<<RUBY)],
Core.new
Main.new
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })
      service.typecheck_source(path: Pathname("lib/main.rb"), target: project.targets.find { _1.name == :main })
      service.typecheck_source(path: Pathname("test/core_test.rb"), target: project.targets.find { _1.name == :test })

      assert_equal [], service.diagnostics.dig(Pathname("lib/core.rb"))
      assert_equal [], service.diagnostics.dig(Pathname("lib/main.rb"))
      assert_equal [], service.diagnostics.dig(Pathname("test/core_test.rb"))
    end
  end

  def test_typecheck__ruby_unreferenced_target
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core_test.rbs") => [ContentChange.string(<<RBS)],
class CoreTest
end
RBS
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
CoreTest.new
RUBY
      Pathname("lib/main.rb") => [ContentChange.string(<<RUBY)],
CoreTest.new
RUBY
      Pathname("test/core_test.rb") => [ContentChange.string(<<RUBY)],
CoreTest.new
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })
      service.typecheck_source(path: Pathname("lib/main.rb"), target: project.targets.find { _1.name == :main })
      service.typecheck_source(path: Pathname("test/core_test.rb"), target: project.targets.find { _1.name == :test })

      service.diagnostics[Pathname("lib/core.rb")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, errors[0]
          assert_equal :CoreTest, error.name
        end
      end
      service.diagnostics[Pathname("lib/main.rb")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, errors[0]
          assert_equal :CoreTest, error.name
        end
      end
      assert_equal [], service.diagnostics.dig(Pathname("test/core_test.rb"))
    end
  end

  def test_validate__signature
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RUBY)],
type core = Array
RUBY
      Pathname("sig/main.rbs") => [ContentChange.string(<<RUBY)],
type main = Array[Integer]
RUBY
    }.tap do |changes|
      service.update(changes: changes)
      service.validate_signature(path: Pathname("sig/core.rbs"), target: project.targets.find { _1.name == :core })
      service.validate_signature(path: Pathname("sig/main.rbs"), target: project.targets.find { _1.name == :main })

      service.diagnostics[Pathname("sig/core.rbs")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        end
      end

      assert_empty service.diagnostics[Pathname("sig/main.rbs")]
    end
  end

  def test_validate__other_target
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class Core
  def foo: () -> Array[Main]
end
RBS
      Pathname("sig/main.rbs") => [ContentChange.string(<<RBS)],
class Main
  def foo: () -> Array[Core]
end
RBS
    }.tap do |changes|
      service.update(changes: changes)
      service.validate_signature(path: Pathname("sig/core.rbs"), target: project.targets.find { _1.name == :core })
      service.validate_signature(path: Pathname("sig/main.rbs"), target: project.targets.find { _1.name == :main })

      assert_empty service.diagnostics[Pathname("sig/core.rbs")]
      assert_empty service.diagnostics[Pathname("sig/main.rbs")]
    end
  end

  def test_validate__unreferenced_target
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
type core = CoreTest
RBS
      Pathname("sig/main.rbs") => [ContentChange.string(<<RBS)],
type main = CoreTest
RBS
      Pathname("sig/core_test.rbs") => [ContentChange.string(<<RBS)],
class CoreTest
end
RBS
    }.tap do |changes|
      service.update(changes: changes)
      service.validate_signature(path: Pathname("sig/core.rbs"), target: project.targets.find { _1.name == :core })
      service.validate_signature(path: Pathname("sig/main.rbs"), target: project.targets.find { _1.name == :main })
      service.validate_signature(path: Pathname("sig/core_test.rbs"), target: project.targets.find { _1.name == :test })

      service.diagnostics[Pathname("sig/core.rbs")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        end
      end
      service.diagnostics[Pathname("sig/main.rbs")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        end
      end
      assert_empty service.diagnostics[Pathname("sig/core_test.rbs")]
    end
  end


  def test_update_signature_3
    # Syntax error in RBS will be reported
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class Account[z]
end
RBS
    }.tap do |changes|
      service.update(changes: changes)
      service.validate_signature(path: Pathname("sig/core.rbs"), target: project.targets.find { _1.name == :core })

      # SyntaxError is reported to all of the targets
      service.diagnostics[Pathname("sig/core.rbs")].tap do |errors|
        assert_equal 4, errors.size
        errors.each do |error|
          assert_instance_of Diagnostic::Signature::SyntaxError, error
        end
      end
    end
  end

  def test_signature_error_unknown_outer_module
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class Foo::Bar::Baz
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      service.validate_signature(path: Pathname("sig/core.rbs"), target: project.targets.find { _1.name == :core })

      service.diagnostics[Pathname("sig/core.rbs")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnknownTypeName, errors[0]
          assert_equal "Cannot find type `::Foo::Bar`", error.header_line
        end
      end
    end
  end

  def test_typecheck__ignore
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("lib/core.rb") => [ContentChange.string(<<~RUBY)],
        # steep:ignore:start
        1+""
        # steep:ignore:end

        foo() # steep:ignore

        bar() # steep:ignore NoMethod
      RUBY
    }.tap do |changes|
      service.update(changes: changes)
      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      assert_equal [], service.diagnostics[Pathname("lib/core.rb")]
    end
  end

  def test_typecheck__ignore_error
    # Ignore diagnostics based on ignore comment

    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("lib/core.rb") => [ContentChange.string(<<~RUBY)],
        # steep:ignore:start

        # steep:ignore

        foo()
      RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      assert_equal(
        [Diagnostic::Ruby::NoMethod, Diagnostic::Ruby::InvalidIgnoreComment, Diagnostic::Ruby::InvalidIgnoreComment],
        service.diagnostics[Pathname("lib/core.rb")].map {|d| d.class }
      )
    end
  end

  def test_typecheck__ignore_redundant
    service = Services::TypeCheckService.new(project: project)
    service.update(changes: reset_changes)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class A
  def foo: -> void
end
RBS
      Pathname("lib/core.rb") => [ContentChange.string(<<RUBY)],
class A
  def foo # steep:ignore
  end
end

1+"" # steep:ignore

# steep:ignore:start
1+2
# steep:ignore:end
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      service.typecheck_source(path: Pathname("lib/core.rb"), target: project.targets.find { _1.name == :core })

      assert_any!(service.diagnostics[Pathname("lib/core.rb")]) do |error|
        assert_instance_of Diagnostic::Ruby::RedundantIgnoreComment, error
        assert_equal "steep:ignore", error.location.source
      end

      assert_any!(service.diagnostics[Pathname("lib/core.rb")]) do |error|
        assert_instance_of Diagnostic::Ruby::RedundantIgnoreComment, error
        assert_equal "steep:ignore:start\n1+2\n# steep:ignore:end", error.location.source
      end
    end
  end

  def test_update__inline
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RBS)],
class Inline
  def foo #: String
    ""
  end
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")

      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_empty diagnostics
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_empty diagnostics
    end
  end

  def test_update__inline__type_error #: void
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RBS)],
class Inline
  def foo #: String
    123
  end
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")

      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Ruby::MethodBodyTypeMismatch, error
      end
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_empty diagnostics
    end
  end

  def test_update__inline__validation_error #: void
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RBS)],
class Inline
  def foo #: String)
    ""
  end
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")

      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_empty diagnostics
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InlineDiagnostic, error
        assert_instance_of RBS::InlineParser::Diagnostic::AnnotationSyntaxError, error.diagnostic
        assert_equal ": String)", error.location.source
      end
    end
  end

  def test_update__inline__mixin_unknown_type_name
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
module M[T]
  def foo: () -> T
end
RBS
      Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)],
class Example
  include M #[Str]
end
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")
      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal ::RBS::TypeName.parse("Str"), error.name
        assert_equal "Cannot find type `Str`", error.header_line
      end
    end
  end

  def test_update__inline__mixin_passing_unexpected_type_arguments
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RBS)],
module M
end

class A
  include M #[String, Integer]
end

class B
  extend M #[String]
end
RBS
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")
      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Ruby::UnexpectedError, error
        assert_instance_of RBS::InvalidTypeApplicationError, error.error
      end
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics

      # Check for too many type arguments error
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        assert_equal ::RBS::TypeName.new(name: :M, namespace: RBS::Namespace.root), error.name
        assert_equal 2, error.args.size
        assert_equal [], error.params
        assert_equal "include M", error.location.source
        assert_equal "Type `::M` is not generic but used as a generic type with 2 arguments", error.header_line
      end

      # Check for too few type arguments error
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        assert_equal ::RBS::TypeName.new(name: :M, namespace: RBS::Namespace.root), error.name
        assert_equal 1, error.args.size
        assert_equal [], error.params
        assert_equal "extend M", error.location.source
        assert_equal "Type `::M` is not generic but used as a generic type with 1 arguments", error.header_line
      end
    end
  end

  def test_update__inline__inheritance_non_constant_super_class
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)],
class MyClass
end

klass = MyClass

# Super class is not a constant - this should be detected as a limitation
class Foo < klass
  #: () -> String
  def test
    "foo"
  end
end
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")
      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      assert_empty diagnostics
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics

      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InlineDiagnostic, error
        assert_instance_of RBS::InlineParser::Diagnostic::NonConstantSuperClassName, error.diagnostic
        assert_equal "klass", error.location.source
      end
    end
  end

  def test_update__inline__inheritance_generic_missing_type_args
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("sig/core.rbs") => [ContentChange.string(<<RBS)],
class SuperClass[T]
  def foo: () -> T
end
RBS
      Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)],
class ChildClass < SuperClass
end

class ChildClass2 < SuperClass #[String, void]
end
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")
      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_nil diagnostics
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics

      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        assert_equal "SuperClass", error.location.source
      end

      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        assert_equal "SuperClass #[String, void]", error.location.source
      end
    end
  end

  def test_update__inline__instance_variable_duplication
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)],
class Person
  # @rbs @name: String
  # @rbs @age: Integer
  # @rbs @name: String? -- This is a duplicate

  def initialize(name, age)
    @name = name
    @age = age
  end
end
RUBY
    }.tap do |changes|
      service.update(changes: changes)

      assert_operator service.source_files, :key?, Pathname("lib/inline.rb")
      assert_operator service, :signature_file?, Pathname("lib/inline.rb")
      assert_operator service, :source_file?, Pathname("lib/inline.rb")
    end

    service.typecheck_source(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      # Type checking may pass or fail depending on when the duplication is detected
    end

    service.validate_signature(path: Pathname("lib/inline.rb"), target: project.targets.find { _1.name == :inline }).tap do |diagnostics|
      assert_instance_of Array, diagnostics
      # The duplication error is reported during signature validation
      assert_any!(diagnostics) do |error|
        assert_instance_of Diagnostic::Signature::InstanceVariableDuplicationError, error
        assert_equal :@name, error.variable_name
        assert_equal RBS::TypeName.new(name: :Person, namespace: RBS::Namespace.root), error.type_name
        assert_equal "Duplicated instance variable name `@name` in `::Person`", error.header_line
        assert_equal "@rbs @name: String? -- This is a duplicate", error.location.source
      end
    end
  end
end
