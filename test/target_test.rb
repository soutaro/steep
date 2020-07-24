require "test_helper"

module Steep
  class TargetTest < Minitest::Test
    include TestHelper

    def test_test_pattern
      assert Project::Target.test_pattern(["lib/*"], Pathname("lib/foo.rb"), ext: ".rb")
      assert Project::Target.test_pattern(["lib"], Pathname("lib/foo.rb"), ext: ".rb")
      refute Project::Target.test_pattern(["lib"], Pathname("test/foo_test.rb"), ext: ".rb")
    end

    def test_success_type_check
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source Pathname("lib/foo.rb"), <<-EOF
class Foo
end
      EOF

      target.add_signature Pathname("sig/foo.rbs"), <<-EOF
class Foo
end
      EOF

      target.type_check

      assert_equal Project::Target::TypeCheckStatus, target.status.class
      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::TypeCheckStatus, file.status.class
        assert_empty file.status.typing.errors
      end

      target.update_source Pathname("lib/foo.rb"), <<-EOF
class Foo
end

# @type var x: Integer
x = ""
      EOF

      target.type_check

      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::TypeCheckStatus, file.status.class
        refute_empty file.status.typing.errors
      end

      target.update_source Pathname("lib/foo.rb"), <<-EOF
class Foo

# @type var x: Integer
x = ""
      EOF

      target.type_check

      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::ParseErrorStatus, file.status.class
      end
    end

    def test_success_type_check_partial
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source Pathname("lib/foo.rb"), <<-EOF
class Foo
end
      EOF

      target.add_source Pathname("lib/bar.rb"), <<-EOF
class Bar
end
      EOF

      target.add_signature Pathname("sig/foo.rbs"), <<-EOF
class Foo
end
      EOF

      target_sources = [target.source_files[Pathname("lib/foo.rb")]]

      target.type_check(target_sources: target_sources, validate_signatures: false)

      assert_equal Project::Target::TypeCheckStatus, target.status.class
      assert_equal target_sources.map(&:path), target.status.type_check_sources.map(&:path)
      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::TypeCheckStatus, file.status.class
        assert_empty file.status.typing.errors
      end
    end

    def test_success_type_check_with_unreported_errors
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new.tap { |o| o.apply_lenient_typing_options! },
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source Pathname("lib/foo.rb"), <<-EOF
Foo = 1
      EOF

      target.type_check

      assert_equal Project::Target::TypeCheckStatus, target.status.class
      assert_empty target.errors
      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::TypeCheckStatus, file.status.class
        refute_empty file.status.typing.errors
      end
    end

    def test_signature_syntax_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source "lib/foo.rb", <<-EOF
class Foo
end
      EOF

      target.add_signature "sig/foo.rbs", <<-EOF
class Foo
      EOF

      target.type_check

      assert_equal Project::Target::SignatureSyntaxErrorStatus, target.status.class
    end

    def test_signature_validation_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source "lib/foo.rb", <<-EOF
class Foo
end
      EOF

      target.add_signature "sig/foo.rbs", <<-EOF
class Foo < Array
end
      EOF

      target.type_check

      assert_equal Project::Target::SignatureValidationErrorStatus, target.status.class
    end

    def test_signature_mixed_module_class_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_signature "sig/foo.rbs", <<-EOF
class Foo
end

module Foo
end
      EOF

      target.type_check

      assert_equal Project::Target::SignatureOtherErrorStatus, target.status.class

      exn = target.status.error

      assert_instance_of RBS::DuplicatedDeclarationError, exn
      assert_equal "::Foo", exn.name.to_s
    end

    def test_annotation_syntax_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_patterns: ["lib"],
        ignore_patterns: [],
        signature_patterns: ["sig"]
      )

      target.add_source Pathname("lib/foo.rb"), <<-EOF
class Foo
  def test
    # @type var x:
  end
end
      EOF

      target.add_signature Pathname("sig/foo.rbs"), <<-EOF
class Foo
  def test: () -> void
end
      EOF

      target.type_check

      assert_equal Project::Target::TypeCheckStatus, target.status.class

      target.source_files[Pathname("lib/foo.rb")].tap do |file|
        assert_equal Project::SourceFile::AnnotationSyntaxErrorStatus, file.status.class
        assert_equal "3:5...3:18", file.status.location.to_s
      end
    end
  end
end
