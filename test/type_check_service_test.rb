require_relative "test_helper"

class TypeCheckServiceTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  TypeCheckService = Services::TypeCheckService
  TargetRequest = Services::TypeCheckService::TargetRequest

  def project
    @project ||= Project.new(steepfile_path: Pathname.pwd + "Steepfile").tap do |project|
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "lib.rbs", "private.rbs", "private/*.rbs"
end

target :test do
  check "test"
  signature "lib.rbs", "test.rbs"
end
EOF
    end
  end

  def assignment
    @assignment ||= Services::PathAssignment.new(max_index: 1, index: 0)
  end

  def reported_diagnostics
    @reported_diagnostics ||= {}
  end

  def reporter
    -> ((path, diagnostics)) {
      formatter = Diagnostic::LSPFormatter.new({}, **{})
      reported_diagnostics[path] = diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
    }
  end

  def assert_empty_diagnostics(enum)
    enum.each do |path, diagnostics|
      assert_instance_of Pathname, path
      assert_empty diagnostics
    end
  end

  def test_update_files
    service = Services::TypeCheckService.new(project: project)

    # lib.rbs is used in both `lib` and `test`
    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Customer
end
RBS
    }.tap do |changes|
      requests = service.update(changes: changes)

      assert_predicate requests[:lib], :signature_updated?
      assert_predicate requests[:test], :signature_updated?
    end

    # private.rbs is used only in both `lib`
    {
      Pathname("private.rbs") => [ContentChange.string(<<RBS)],
module CustomerHelper
end
RBS
    }.tap do |changes|
      requests = service.update(changes: changes)

      assert_predicate requests[:lib], :signature_updated?
      assert_nil requests[:test]
    end

    # test/customer_test.rb is in `test`
    {
      Pathname("test/customer_test.rb") => [ContentChange.string(<<RUBY)],
RUBY
    }.tap do |changes|
      requests = service.update(changes: changes)

      assert_nil requests[:lib]
      requests[:test].tap do |request|
        refute_predicate request, :signature_updated?
        assert_equal Set[Pathname("test/customer_test.rb")], request.source_paths
      end
    end

    # test.rbs is in `test`
    {
      Pathname("test.rbs") => [ContentChange.string(<<RBS)],
class CustomerTest
end
RBS
    }.tap do |changes|
      requests = service.update(changes: changes)

      assert_nil requests[:lib]
      requests[:test].tap do |request|
        assert_predicate request, :signature_updated?
        assert_equal Set[Pathname("test/customer_test.rb")], request.source_paths
      end
    end
  end

  def test_update_ruby_syntax_error
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/syntax_error.rb") => [ContentChange.string(<<RUBY)],
class Account
RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      service.source_files[Pathname("lib/syntax_error.rb")].tap do |file|
        assert_any!(file.errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::SyntaxError, error
          assert_equal 2, error.location.line
          assert_equal 0, error.location.column
          assert_equal 2, error.location.last_line
          assert_equal 0, error.location.last_column
        end
      end

      reported_diagnostics.clear
    end
  end

  def test_update_encoding_error
    service = Services::TypeCheckService.new(project: project)

    broken = "寿限無寿限無".encode(Encoding::EUC_JP)

    broken.force_encoding(Encoding::UTF_8)

    {
      Pathname("lib/syntax_error.rb") => [ContentChange.string(broken)]
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      service.source_files[Pathname("lib/syntax_error.rb")].tap do |file|
        assert_nil file.errors
        assert_equal "", file.content
      end

      reported_diagnostics.clear
    end
  end

  def test_update_ruby_annotation_syntax_error
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/annotation_syntax_error.rb") => [ContentChange.string(<<RUBY)],
class Account
  # @type self: Array[
end
RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      service.source_files[Pathname("lib/annotation_syntax_error.rb")].tap do |file|
        assert_any!(file.errors, size: 1) do |error|
          assert_instance_of Diagnostic::Ruby::SyntaxError, error
          assert_equal "Array[", error.location.source
          assert_equal "Syntax error caused by token `pEOF`", error.message
        end
      end

      reported_diagnostics.clear
    end
  end

  def test_update_ruby
    # Update Ruby code notifies diagnostics found in updated files and sets up #diagnostics.

    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Account
end
RBS
      Pathname("lib/no_error.rb") => [ContentChange.string(<<RUBY)],
class Account
end
RUBY
      Pathname("lib/type_error.rb") => [ContentChange.string(<<RUBY)],
1+""
RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_equal [], reported_diagnostics.dig(Pathname("lib/no_error.rb"))
      assert_equal "Ruby::UnresolvedOverloading", reported_diagnostics.dig(Pathname("lib/type_error.rb"), 0, :code)

      assert_equal [], service.diagnostics.dig(Pathname("lib/no_error.rb"))

      service.diagnostics[Pathname("lib/type_error.rb")].tap do |errors|
        assert_equal 1, errors.size
        assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, errors[0]
      end

      reported_diagnostics.clear
    end
  end

  def test_update_signature_1
    # Updating signature runs type check
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/a.rb") => [ContentChange.string(<<RUBY)],
account = Account.new
RUBY
    }.tap do |changes|
      # Account is not defined.
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_equal "Ruby::UnknownConstant", reported_diagnostics.dig(Pathname("lib/a.rb"), 0, :code)
      service.diagnostics[Pathname("lib/a.rb")].tap do |errors|
        assert_equal 1, errors.size
        assert_instance_of Diagnostic::Ruby::UnknownConstant, errors[0]
      end

      reported_diagnostics.clear
    end

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RUBY)],
class Account
end
RUBY
    }.tap do |changes|
      # Adding RBS file removes the type errors.
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_empty_diagnostics reported_diagnostics
      assert_empty_diagnostics service.diagnostics

      reported_diagnostics.clear
    end
  end

  def test_update_signature_2
    # Reports signature errors from all targets
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Account
  def foo: () -> User[String]
  def bar: () -> User
end
RBS
      Pathname("private.rbs") => [ContentChange.string(<<RBS)],
class User[A]
end
RBS
      Pathname("test.rbs") => [ContentChange.string(<<RBS)],
class User
end
RBS
    }.tap do |changes|
      # lib target reports an error on `User`
      # test target reports an error on `User[String]`
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 2, errors.size
        assert_any!(errors) do |error|
          # One error is reported from `test` target.
          assert_equal "RBS::InvalidTypeApplication", error[:code]
          assert_equal 1, error.dig(:range, :start, :line)
        end
        assert_any!(errors) do |error|
          # Another error is reported from `lib` target.
          assert_equal "RBS::InvalidTypeApplication", error[:code]
          assert_equal 2, error.dig(:range, :start, :line)
        end
      end

      service.diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 2, errors.size
        errors.each do |error|
          assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        end
      end

      reported_diagnostics.clear
    end
  end

  def test_update_signature_3
    # Syntax error in RBS will be reported
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Account[z]
end
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 1, errors.size
        assert_equal "RBS::SyntaxError", errors[0][:code]
      end

      service.diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 2, errors.size
        errors.each do |error|
          assert_instance_of Diagnostic::Signature::SyntaxError, error
        end
      end

      reported_diagnostics.clear
    end
  end

  def test_update_signature_4
    # Target with syntax error RBS won't report new type errors.
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/a.rb") => [ContentChange.string(<<RBS)],
1 + ""
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib/a.rb")].tap do |errors|
        assert_equal 1, errors.size
        assert_equal "Ruby::UnresolvedOverloading", errors[0][:code]
      end

      reported_diagnostics.clear
    end

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Account[z]
end
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 1, errors.size
        assert_equal "RBS::SyntaxError", errors[0][:code]
      end

      # No error reported for lib/a.rb
      reported_diagnostics[Pathname("lib/a.rb")].tap do |errors|
        assert_nil errors
      end

      service.diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_equal 2, errors.size
        errors.each do |error|
          assert_instance_of Diagnostic::Signature::SyntaxError, error
        end
      end

      # #diagnostics not updated
      service.diagnostics[Pathname("lib/a.rb")].tap do |errors|
        assert_equal 1, errors.size
        errors.each do |error|
          assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, error
        end
      end

      reported_diagnostics.clear
    end
  end

  def test_update_signature_5
    # Target with syntax error RBS won't report new validation errors.
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class A
end
RBS
      Pathname("private.rbs") => [ContentChange.string(<<RBS)],
B: Array
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_empty errors
      end
      reported_diagnostics[Pathname("private.rbs")].tap do |errors|
        assert_any! errors, size: 1 do |error|
          assert_equal "RBS::InvalidTypeApplication", error[:code]
        end
      end

      reported_diagnostics.clear
    end

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class A < FooBar
end
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_any! errors, size: 1 do |error|
          assert_equal "RBS::UnknownTypeName", error[:code]
        end
      end

      # No error can be reported/registered because of ancestor error.
      reported_diagnostics[Pathname("private.rbs")].tap do |errors|
        assert_empty errors
      end
      service.diagnostics[Pathname("private.rbs")].tap do |errors|
        assert_empty errors
      end

      reported_diagnostics.clear
    end
  end

  def test_update_signature_6
    # Recovering from syntax error test
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("private.rbs") => [ContentChange.string(<<RBS)],
class A
RBS
      Pathname("private/test.rbs") => [ContentChange.string(<<RBS)],
class B
end
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("private.rbs")].tap do |errors|
        assert_any! errors, size: 1 do |error|
          assert_equal "RBS::SyntaxError", error[:code]
        end
      end
      reported_diagnostics[Pathname("private/test.rbs")].tap do |errors|
        assert_nil errors
      end

      reported_diagnostics.clear
    end

    {
      Pathname("private.rbs") => [ContentChange.string(<<RBS)],
class A
  def foo: () -> B
end
RBS
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_empty_diagnostics reported_diagnostics
      assert_empty_diagnostics service.diagnostics

      reported_diagnostics.clear
    end
  end

  def test_signature_error_unknown_outer_module
    # Recovering from syntax error test
    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib.rbs") => [ContentChange.string(<<RBS)],
class Foo::Bar::Baz
end
RBS
      Pathname("lib/a.rb") => [ContentChange.string(<<RUBY)],
1+2
RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      reported_diagnostics[Pathname("lib.rbs")].tap do |errors|
        assert_any!(errors, size: 1) do |error|
          assert_equal "RBS::UnknownTypeName", error[:code]
          assert_equal "Cannot find type `::Foo::Bar`", error[:message]
        end
      end

      reported_diagnostics[Pathname("lib/a.rb")].tap do |errors|
        assert_empty errors
      end
    end
  end

  def test_update_ruby__ignore
    # Ignore diagnostics based on ignore comment

    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/a.rb") => [ContentChange.string(<<~RUBY)],
        # steep:ignore:start
        1+""
        # steep:ignore:end

        foo() # steep:ignore

        bar() # steep:ignore NoMethod
      RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_equal [], reported_diagnostics.dig(Pathname("lib/a.rb"))

      reported_diagnostics.clear
    end
  end

  def test_update_ruby__ignore_error
    # Ignore diagnostics based on ignore comment

    service = Services::TypeCheckService.new(project: project)

    {
      Pathname("lib/a.rb") => [ContentChange.string(<<~RUBY)],
        # steep:ignore:start

        # steep:ignore

        foo()
      RUBY
    }.tap do |changes|
      service.update_and_check(changes: changes, assignment: assignment, &reporter)

      assert_equal ["Ruby::NoMethod", "Ruby::InvalidIgnoreComment", "Ruby::InvalidIgnoreComment"], reported_diagnostics.dig(Pathname("lib/a.rb")).map {|d| d[:code] }

      reported_diagnostics.clear
    end
  end
end
