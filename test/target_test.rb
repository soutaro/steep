require "test_helper"

module Steep
  class TargetTest < Minitest::Test
    include TestHelper

    def test_environment_loader
      Dir.mktmpdir do |dir|
        path = Pathname(dir)

        (path + "vendor/repo").mkpath
        (path + "vendor/core").mkpath

        Project::Target.construct_env_loader(
          options: Project::Options.new.tap {|opts|
            opts.repository_paths << path + "vendor/repo"
          }
        ).tap do |loader|
          refute_nil loader.core_root

          assert_includes loader.repository.dirs, RBS::Repository::DEFAULT_STDLIB_ROOT
          assert_includes loader.repository.dirs, path + "vendor/repo"
        end

        Project::Target.construct_env_loader(
          options: Project::Options.new.tap {|opts|
            opts.vendor_path = path + "vendor/core"
            opts.repository_paths << path + "vendor/repo"
          }
        ).tap do |loader|
          assert_nil loader.core_root

          assert_includes loader.dirs, path + "vendor/core"
          refute_includes loader.repository.dirs, RBS::Repository::DEFAULT_STDLIB_ROOT
          assert_includes loader.repository.dirs, path + "vendor/repo"
        end
      end
    end

    def test_success_type_check
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
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
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
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
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
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
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
      )

      target.add_signature "sig/foo.rbs", <<-EOF
class Foo
      EOF

      target.add_signature "sig/bar.rbs", <<-EOF
interface _Bar
  def self.foo: () -> void
end
      EOF

      target.type_check

      assert_equal Project::Target::SignatureErrorStatus, target.status.class

      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of RBS::Parser::SemanticsError, error.exception
        assert_equal "def self.foo: () -> void", error.location.source
      end

      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of RBS::Parser::SyntaxError, error.exception
      end
    end

    def test_signature_validation_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
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

      assert_equal Project::Target::SignatureErrorStatus, target.status.class
    end

    def test_signature_mixed_module_class_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
      )

      target.add_signature "sig/foo.rbs", <<-EOF
class Foo
end

module Foo
end
      EOF

      target.type_check

      assert_equal Project::Target::SignatureErrorStatus, target.status.class

      assert_any! target.status.errors do |error|
        assert_instance_of Diagnostic::Signature::DuplicatedDeclaration, error
        assert_equal TypeName("::Foo"), error.type_name
      end
    end

    def test_annotation_syntax_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
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
        assert_equal "lib/foo.rb:3:5...3:18", file.status.location.to_s
      end
    end

    def test_signature_other_error
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
      )

      target.add_signature Pathname("lib/foo.rbs"), <<-EOF.force_encoding(Encoding::UTF_32)
class Foo
end
      EOF

      assert_raises ArgumentError do
        target.type_check
      end
    end

    def test_signature_error_duplicated_decl
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
      )

      target.add_signature Pathname("lib/foo.rbs"), <<-EOF
class Foo
end

Foo: Integer
      EOF

      target.add_signature Pathname("lib/bar.rbs"), <<-EOF
module Bar
end

Bar: Integer
      EOF

      target.type_check

      assert_equal Project::Target::SignatureErrorStatus, target.status.class

      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of Diagnostic::Signature::DuplicatedDeclaration, error
        assert_equal "Foo: Integer", error.location.source
      end

      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of Diagnostic::Signature::DuplicatedDeclaration, error
        assert_equal "Bar: Integer", error.location.source
      end
    end

    def test_signature_error_recursive_super
      target = Project::Target.new(
        name: :foo,
        options: Project::Options.new,
        source_pattern: Project::Pattern.new(patterns: ["lib"], ext: ".rb"),
        signature_pattern: Project::Pattern.new(patterns: ["sig"], ext: ".rbs")
      )

      target.add_signature Pathname("lib/foo.rbs"), <<-EOF
class Foo < Bar
end

class Bar < Foo
end
      EOF

      target.type_check

      assert_equal Project::Target::SignatureErrorStatus, target.status.class
      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of Diagnostic::Signature::RecursiveAncestor, error
        assert_equal "class Foo < Bar\nend", error.location.source
      end
      assert_any!(target.status.errors, size: 2) do |error|
        assert_instance_of Diagnostic::Signature::RecursiveAncestor, error
        assert_equal "class Bar < Foo\nend", error.location.source
      end
    end
  end
end
