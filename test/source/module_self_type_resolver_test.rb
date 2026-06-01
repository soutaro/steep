require_relative "../test_helper"

class Steep::Source::ModuleSelfTypeResolverTest < Minitest::Test
  Resolver = Steep::Source::ModuleSelfTypeResolver

  # --- concern with namespace ---

  def test_concern_injects_self_and_instance
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        included do
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/notifiable.rb", source)

    assert_includes result, "# @type self: singleton(Post) & singleton(Post::Notifiable)"
    assert_includes result, "# @type instance: Post & Post::Notifiable"
  end

  def test_concern_annotations_appended_at_end_of_file
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        included do
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/notifiable.rb", source)
    lines = result.lines

    module_close_idx = lines.rindex { |l| l.strip == "end" }
    self_idx         = lines.index { |l| l.include?("@type self:") }
    instance_idx     = lines.index { |l| l.include?("@type instance:") }

    assert self_idx > module_close_idx
    assert instance_idx > module_close_idx
  end

  def test_concern_original_line_numbers_preserved
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        def notify
          "hello"
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/notifiable.rb", source)

    # Every original line must appear at the same 1-based index in the result
    source.lines.each_with_index do |line, i|
      assert_equal line, result.lines[i], "Line #{i + 1} shifted after annotation"
    end
  end

  # --- plain module with namespace ---

  def test_plain_module_injects_only_instance
    source = <<~RUBY
      module Post::Taggable
        def tag_names
          tags.map(&:name)
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/taggable.rb", source)

    assert_includes result, "# @type instance: Post & Post::Taggable"
    refute_includes result, "@type self:"
  end

  def test_plain_module_annotation_appended_at_end_of_file
    source = <<~RUBY
      module Post::Taggable
        def tag_names
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/taggable.rb", source)
    lines = result.lines

    module_close_idx = lines.rindex { |l| l.strip == "end" }
    instance_idx     = lines.index { |l| l.include?("@type instance:") }

    assert instance_idx > module_close_idx
  end

  # --- idempotency ---

  def test_already_annotated_concern_is_unchanged
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        # @type self: singleton(Post) & singleton(Post::Notifiable)
        # @type instance: Post & Post::Notifiable

        included do
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/notifiable.rb", source)

    assert_equal source, result
  end

  def test_already_annotated_plain_module_is_unchanged
    source = <<~RUBY
      module Post::Taggable
        # @type instance: Post & Post::Taggable

        def tag_names
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/taggable.rb", source)

    assert_equal source, result
  end

  # --- app/controllers/concerns/ ---

  def test_controller_concern_injects_instance_annotation
    source = <<~RUBY
      module FilterConfiguration
        extend ActiveSupport::Concern

        def configure_filter(name)
        end
      end
    RUBY

    result = Resolver.annotate("app/controllers/concerns/filter_configuration.rb", source)

    assert_includes result, "# @type self: singleton(ApplicationController) & singleton(FilterConfiguration)"
    assert_includes result, "# @type instance: ApplicationController & FilterConfiguration"
  end

  def test_controller_concern_plain_module_injects_only_instance
    source = <<~RUBY
      module FilterConfiguration
        def configure_filter(name)
        end
      end
    RUBY

    result = Resolver.annotate("app/controllers/concerns/filter_configuration.rb", source)

    assert_includes result, "# @type instance: ApplicationController & FilterConfiguration"
    refute_includes result, "@type self:"
  end

  def test_already_annotated_controller_concern_is_unchanged
    source = <<~RUBY
      module FilterConfiguration
        extend ActiveSupport::Concern

        # @type self: singleton(ApplicationController) & singleton(FilterConfiguration)
        # @type instance: ApplicationController & FilterConfiguration

        def configure_filter(name)
        end
      end
    RUBY

    result = Resolver.annotate("app/controllers/concerns/filter_configuration.rb", source)

    assert_equal source, result
  end

  # --- files outside app/models/ and app/helpers/ ---

  def test_non_models_non_helpers_file_is_unchanged
    source = <<~RUBY
      module SomeModule
        def help; end
      end
    RUBY

    result = Resolver.annotate("lib/some_module.rb", source)

    assert_equal source, result
  end

  # --- app/helpers/ ---

  def test_helper_injects_instance_annotation
    source = <<~RUBY
      module PostsHelper
        def post_status_badge(post)
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/posts_helper.rb", source)

    assert_includes result, "# @type instance: ApplicationController & PostsHelper"
    refute_includes result, "@type self:"
  end

  def test_helper_annotation_appended_at_end_of_file
    source = <<~RUBY
      module PostsHelper
        def post_status_badge(post)
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/posts_helper.rb", source)
    lines = result.lines

    module_close_idx = lines.rindex { |l| l.strip == "end" }
    instance_idx     = lines.index { |l| l.include?("@type instance:") }

    assert instance_idx > module_close_idx
  end

  def test_application_helper_injects_instance_annotation
    source = <<~RUBY
      module ApplicationHelper
        def current_year
          Time.current.year
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/application_helper.rb", source)

    assert_includes result, "# @type instance: ApplicationController & ApplicationHelper"
  end

  def test_helper_concern_injects_self_and_instance
    source = <<~RUBY
      module PostsHelper
        extend ActiveSupport::Concern

        included do
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/posts_helper.rb", source)

    assert_includes result, "# @type self: singleton(ApplicationController) & singleton(PostsHelper)"
    assert_includes result, "# @type instance: ApplicationController & PostsHelper"
  end

  def test_already_annotated_helper_is_unchanged
    source = <<~RUBY
      module PostsHelper
        # @type instance: ApplicationController & PostsHelper

        def post_status_badge(post)
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/posts_helper.rb", source)

    assert_equal source, result
  end

  def test_helper_full_absolute_path
    source = <<~RUBY
      module PostsHelper
        def help; end
      end
    RUBY

    result = Resolver.annotate("/home/user/myapp/app/helpers/posts_helper.rb", source)

    assert_includes result, "# @type instance: ApplicationController & PostsHelper"
  end

  def test_namespaced_helper
    source = <<~RUBY
      module Admin::PostsHelper
        def admin_badge(post)
        end
      end
    RUBY

    result = Resolver.annotate("app/helpers/admin/posts_helper.rb", source)

    assert_includes result, "# @type instance: ApplicationController & Admin::PostsHelper"
  end

  # --- module without namespace (Strategy B not yet supported) ---

  def test_unnamespaced_module_is_unchanged
    source = <<~RUBY
      module Taggable
        def tag_names
        end
      end
    RUBY

    result = Resolver.annotate("app/models/taggable.rb", source)

    assert_equal source, result
  end

  # --- full path ---

  def test_full_absolute_path
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern
      end
    RUBY

    result = Resolver.annotate("/home/user/myapp/app/models/post/notifiable.rb", source)

    assert_includes result, "# @type self: singleton(Post) & singleton(Post::Notifiable)"
    assert_includes result, "# @type instance: Post & Post::Notifiable"
  end

  def test_pathname_object
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern
      end
    RUBY

    result = Resolver.annotate(Pathname("app/models/post/notifiable.rb"), source)

    assert_includes result, "# @type self: singleton(Post) & singleton(Post::Notifiable)"
  end

  # --- app/models/concerns/ directory (Rails autoload root, no namespace) ---

  def test_concern_under_concerns_directory_strips_concerns_prefix
    source = <<~RUBY
      module Test::Filtrable
        extend ActiveSupport::Concern
      end
    RUBY

    result = Resolver.annotate("app/models/concerns/test/filtrable.rb", source)

    assert_includes result, "singleton(Test) & singleton(Test::Filtrable)"
    assert_includes result, "# @type instance: Test & Test::Filtrable"
    refute_includes result, "Concerns"
  end

  def test_concern_directly_under_concerns_directory
    source = <<~RUBY
      module Taggable
        extend ActiveSupport::Concern
      end
    RUBY

    # concerns/taggable.rb → module_name = "Taggable" → parts.size < 2 → skip
    result = Resolver.annotate("app/models/concerns/taggable.rb", source)

    assert_equal source, result
  end

  # --- snake_case to CamelCase conversion ---

  def test_snake_case_file_name_is_camelized
    source = <<~RUBY
      module User::PasswordRecoverable
        extend ActiveSupport::Concern
      end
    RUBY

    result = Resolver.annotate("app/models/user/password_recoverable.rb", source)

    assert_includes result, "singleton(User) & singleton(User::PasswordRecoverable)"
  end

  # --- nested namespace (module declared inside a class/module wrapper) ---
  #
  # A trailing end-of-file comment attaches to the OUTER scope, so Steep ignores
  # it for the inner module and `self` falls back to `Object & User::Idade`.
  # For nested declarations the annotation must go *inside* the innermost module
  # body instead.

  def test_nested_module_in_class_inserts_annotation_inside_module_body
    source = <<~RUBY
      class User
        module Idade
          def idade
            data_nascimento
          end
        end
      end
    RUBY

    result = Resolver.annotate("app/models/user/idade.rb", source)
    lines = result.lines

    instance_idx  = lines.index { |l| l.include?("@type instance: User & User::Idade") }
    refute_nil instance_idx, "instance annotation should be injected"

    # The annotation lands inside the module body: before the module's `end`
    # (second-to-last) and the class's `end` (last), not after both.
    end_indices = lines.each_index.select { |i| lines[i].strip == "end" }
    assert instance_idx < end_indices[-2], "annotation must be inside the module body, not after its `end`"
    # And indented to the module body level (4 spaces).
    assert_match(/\A    # @type instance:/, lines[instance_idx])
  end

  def test_nested_concern_in_module_inserts_both_annotations_inside_body
    source = <<~RUBY
      module Post
        module Notifiable
          extend ActiveSupport::Concern

          def notify
          end
        end
      end
    RUBY

    result = Resolver.annotate("app/models/post/notifiable.rb", source)
    lines = result.lines

    self_idx     = lines.index { |l| l.include?("@type self: singleton(Post) & singleton(Post::Notifiable)") }
    instance_idx = lines.index { |l| l.include?("@type instance: Post & Post::Notifiable") }
    refute_nil self_idx
    refute_nil instance_idx

    end_indices = lines.each_index.select { |i| lines[i].strip == "end" }
    assert self_idx < end_indices[-2], "self annotation must be inside the inner module body"
    assert instance_idx < end_indices[-2], "instance annotation must be inside the inner module body"
  end

  def test_nested_module_preserves_method_line_numbers
    source = <<~RUBY
      class User
        module Idade
          def idade
            data_nascimento
          end
        end
      end
    RUBY

    result = Resolver.annotate("app/models/user/idade.rb", source)

    # Lines through the method body are unchanged; only the trailing `end`s shift.
    %w[def\ idade data_nascimento].each_with_index do |needle, _|
      src_idx = source.lines.index { |l| l.include?(needle.tr("\\", " ")) }
      assert_equal source.lines[src_idx], result.lines[src_idx], "method body line shifted"
    end
  end

  def test_nested_module_falls_back_to_append_on_unparseable_source
    # Syntactically broken source: Prism can't locate the scope, so the resolver
    # must not raise — it falls back to appending at end of file.
    source = "class User\n  module Idade\n    def idade\n"

    result = Resolver.annotate("app/models/user/idade.rb", source)

    assert_includes result, "# @type instance: User & User::Idade"
  end
end
