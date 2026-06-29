require_relative "../test_helper"
require "tmpdir"

class Steep::Source::ModuleSelfTypesTest < Minitest::Test
  M = Steep::Source::ModuleSelfTypes

  CONCERN = ["# @type self: singleton(Post) & singleton(Post::Notifiable)",
             "# @type instance: Post & Post::Notifiable"].freeze

  # --- inject: placement (the genuinely-Steep behavior) ---

  def test_inject_appends_at_end_for_top_level_module
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        included do
        end
      end
    RUBY

    result = M.inject(source, annotations: CONCERN, anchor: "Notifiable")
    lines = result.lines

    module_close_idx = lines.rindex { |l| l.strip == "end" }
    self_idx         = lines.index { |l| l.include?("@type self:") }
    instance_idx     = lines.index { |l| l.include?("@type instance:") }

    assert self_idx > module_close_idx
    assert instance_idx > module_close_idx
    assert_includes result, CONCERN[0]
    assert_includes result, CONCERN[1]
  end

  def test_inject_preserves_original_line_numbers
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        def notify
          "hello"
        end
      end
    RUBY

    result = M.inject(source, annotations: CONCERN, anchor: "Notifiable")

    source.lines.each_with_index do |line, i|
      assert_equal line, result.lines[i], "Line #{i + 1} shifted after annotation"
    end
  end

  def test_inject_into_nested_module_goes_inside_body
    source = <<~RUBY
      module Search
        class Record
          module SQLite
            extend ActiveSupport::Concern
          end
        end
      end
    RUBY
    annotations = ["# @type self: singleton(Search::Record) & singleton(Search::Record::SQLite)",
                   "# @type instance: Search::Record & Search::Record::SQLite"]

    result = M.inject(source, annotations: annotations, anchor: "SQLite")
    lines = result.lines

    sqlite_open = lines.index { |l| l.include?("module SQLite") }
    annotation  = lines.index { |l| l.include?("@type self:") }
    closing_ends = lines.each_index.select { |i| lines[i].strip == "end" }

    assert annotation > sqlite_open
    assert annotation < closing_ends.last, "annotation must be inside the body, not after the closing ends"
  end

  def test_inject_is_idempotent
    source = <<~RUBY
      module Post::Notifiable
        extend ActiveSupport::Concern

        # @type self: singleton(Post) & singleton(Post::Notifiable)
        # @type instance: Post & Post::Notifiable

        included do
        end
      end
    RUBY

    assert_equal source, M.inject(source, annotations: CONCERN, anchor: "Notifiable")
  end

  def test_inject_single_instance_annotation
    source = <<~RUBY
      module Post::Taggable
        def tag_names
        end
      end
    RUBY
    annotations = ["# @type instance: Post & Post::Taggable"]

    result = M.inject(source, annotations: annotations, anchor: "Taggable")

    assert_includes result, "# @type instance: Post & Post::Taggable"
    refute_includes result, "@type self:"
  end

  def test_inject_falls_back_to_append_on_unparseable_source
    source = "module Broken\n  def x(\n"
    annotations = ["# @type instance: Foo & Broken"]

    result = M.inject(source, annotations: annotations, anchor: "Broken")

    assert_includes result, "# @type instance: Foo & Broken"
  end

  # --- inject_blocks: @implements into a DSL block body ---

  TAGGABLE = <<~RUBY
    module Post
      module Taggable
        class_methods do
          def default_tag_names
            ["news"]
          end
        end
      end
    end
  RUBY

  BLOCKS = [{ "call" => "class_methods", "implements" => "::Post::Taggable::ClassMethods" }].freeze

  def test_inject_blocks_appends_implements_on_the_opener_line
    result = M.inject_blocks(TAGGABLE, blocks: BLOCKS)
    lines = result.lines

    do_line = lines.find { |l| l.include?("class_methods do") }
    assert_includes do_line, "@implements ::Post::Taggable::ClassMethods",
                    "annotation must ride on the `do` line itself"
    assert_match(/class_methods do # @implements ::Post::Taggable::ClassMethods/, do_line)
  end

  def test_inject_blocks_adds_no_line_and_keeps_every_other_line
    result = M.inject_blocks(TAGGABLE, blocks: BLOCKS)
    lines = result.lines
    original = TAGGABLE.lines

    # No line added → line numbers Steep reports stay aligned with the source.
    assert_equal original.size, lines.size

    original.each_with_index do |orig, i|
      if orig.include?("class_methods do")
        # The opener line only gains a trailing comment.
        assert lines[i].start_with?(orig.chomp), "opener line #{i + 1} must keep its prefix"
        assert_includes lines[i], "@implements"
      else
        assert_equal orig, lines[i], "line #{i + 1} must not move or change"
      end
    end
  end

  def test_inject_blocks_skips_inline_block_rather_than_corrupting_it
    # An inline `{ … }` body shares the opener line; appending a `#` comment
    # there would swallow the body, so the block is left untouched.
    source = "module M\n  class_methods { def x; end }\nend\n"
    assert_equal source, M.inject_blocks(source, blocks: BLOCKS)
  end

  def test_inject_blocks_preserves_lines_before_the_block
    result = M.inject_blocks(TAGGABLE, blocks: BLOCKS)

    # Everything up to and including `class_methods do` is byte-for-byte intact
    # (we insert *after* the `do`).
    prefix = TAGGABLE[0..TAGGABLE.index("class_methods do") + "class_methods do".length - 1]
    assert result.start_with?(prefix)
  end

  def test_inject_blocks_is_idempotent
    once  = M.inject_blocks(TAGGABLE, blocks: BLOCKS)
    twice = M.inject_blocks(once, blocks: BLOCKS)
    assert_equal once, twice
    assert_equal 1, twice.lines.count { |l| l.include?("@implements ::Post::Taggable::ClassMethods") }
  end

  def test_inject_blocks_ignores_unmatched_call_name
    result = M.inject_blocks(TAGGABLE, blocks: [{ "call" => "included", "implements" => "X" }])
    assert_equal TAGGABLE, result
  end

  def test_inject_blocks_skips_call_with_receiver
    source = <<~RUBY
      module Post
        module Taggable
          helper.class_methods do
            def x; end
          end
        end
      end
    RUBY

    assert_equal source, M.inject_blocks(source, blocks: BLOCKS)
  end

  def test_inject_blocks_noop_for_empty_blocks
    assert_equal TAGGABLE, M.inject_blocks(TAGGABLE, blocks: [])
  end

  def test_inject_blocks_falls_back_on_unparseable_source
    source = "module Broken\n  class_methods do\n"
    assert_equal source, M.inject_blocks(source, blocks: BLOCKS)
  end

  # --- entry_for: sidecar loading ---

  def test_entry_for_reads_sidecar_keyed_by_path
    with_sidecar(
      "app/models/search/record/sqlite.rb" => {
        "anchor" => "SQLite",
        "annotations" => ["# @type instance: Search::Record & Search::Record::SQLite"]
      }
    ) do
      entry = M.entry_for("app/models/search/record/sqlite.rb")
      assert_equal "SQLite", entry["anchor"]
      assert_includes entry["annotations"].first, "Search::Record::SQLite"
    end
  end

  def test_entry_for_matches_absolute_path_by_tail
    with_sidecar("app/models/post/taggable.rb" => { "anchor" => "Taggable", "annotations" => [] }) do |dir|
      entry = M.entry_for("#{dir}/app/models/post/taggable.rb")
      assert_equal "Taggable", entry["anchor"]
    end
  end

  def test_entry_for_nil_without_sidecar
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        M.reset!
        assert_nil M.entry_for("app/models/post/taggable.rb")
      end
    end
  ensure
    M.reset!
  end

  def test_entry_for_reloads_after_sidecar_mtime_changes
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        M.reset!
        dump_sidecar({ "a.rb" => { "anchor" => "A", "annotations" => [] } }, mtime: Time.at(1_000_000))
        assert M.entry_for("a.rb")
        assert_nil M.entry_for("b.rb")

        dump_sidecar(
          { "a.rb" => { "anchor" => "A", "annotations" => [] },
            "b.rb" => { "anchor" => "B", "annotations" => [] } },
          mtime: Time.at(2_000_000)
        )
        assert M.entry_for("b.rb"), "regenerated sidecar must be picked up"
      end
    end
  ensure
    M.reset!
  end

  private

  def with_sidecar(table)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        M.reset!
        dump_sidecar(table)
        yield dir
      end
    end
  ensure
    M.reset!
  end

  def dump_sidecar(table, mtime: nil)
    path = Steep::Source::ModuleSelfTypes::DEFAULT_SIDECAR_PATH
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(table))
    File.utime(File.atime(path), mtime, path) if mtime
    M.reset!
  end
end
