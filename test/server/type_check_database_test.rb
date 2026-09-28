require_relative "../test_helper"

class Steep::Server::TypeCheckDatabaseTest < Minitest::Test
  include TestHelper

  include Steep

  # @rbs skip
  TypeCheckDatabase = Server::TypeCheckDatabase

  # @rbs!
  #   class TypeCheckDatabase = Steep::Server::TypeCheckDatabase

  def entry(name, role:, at:, kind: nil) #: TypeCheckDatabase::Entry
    start_line, start_character, end_line, end_character = at
    TypeCheckDatabase::Entry.new(
      name: name,
      role: role,
      kind: kind,
      start_line: start_line,
      start_character: start_character,
      end_line: end_line,
      end_character: end_character
    )
  end

  def diagnostic(message, line: 0) #: untyped
    {
      message: message,
      code: "Ruby::NoMethod",
      severity: 1,
      range: { start: { line: line, character: 0 }, end: { line: line, character: 5 } }
    }
  end

  # Returns `[path, source, start line]` triples of the locations
  def summarize(locations) #: Array[[Pathname, Symbol, Integer]]
    locations.map { |location| [location.path, location.source, location.start_line] }
  end

  def test_diagnostics_merges_tables_and_targets
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    shared = diagnostic("shared")

    database.update_source(path: path, target: :app, diagnostics: [diagnostic("ruby")], entries: [])
    database.update_signature(path: path, target: :app, diagnostics: [shared, diagnostic("app only")])
    database.update_signature(path: path, target: :test, diagnostics: [shared, diagnostic("test only")])

    assert_equal ["ruby", "shared", "app only", "test only"], database.diagnostics(path).map { _1[:message] }
  end

  def test_diagnostics_of_unchecked_file
    database = TypeCheckDatabase.new()

    assert_equal [], database.diagnostics(Pathname("lib/a.rb"))
  end

  def test_skipped_type_check_keeps_previous_result
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [diagnostic("a")],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )

    database.update_source(path: path, target: :app, diagnostics: nil, entries: nil)

    assert_equal ["a"], database.diagnostics(path).map { _1[:message] }
    assert_equal [[path, :ruby, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.entry_count
    assert_equal 1, database.pool.size

    # Skipping the first type checking of a file stores nothing
    database.update_source(path: Pathname("lib/b.rb"), target: :app, diagnostics: nil, entries: nil)

    assert_equal [], database.diagnostics(Pathname("lib/b.rb"))
    assert_equal 1, database.entry_count
  end

  def test_definitions_and_references
    database = TypeCheckDatabase.new()

    database.update_source(
      path: Pathname("lib/a.rb"),
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Foo#bar", role: :definition, at: [1, 6, 1, 9])
      ]
    )
    database.update_source(
      path: Pathname("lib/b.rb"),
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", role: :reference, at: [3, 0, 3, 3]),
        entry("::Foo#bar", role: :reference, at: [3, 4, 3, 7])
      ]
    )

    assert_equal [[Pathname("lib/a.rb"), :ruby, 1]], summarize(database.definitions("::Foo#bar"))
    assert_equal [[Pathname("lib/b.rb"), :ruby, 3]], summarize(database.references("::Foo"))

    assert_equal [], database.definitions("::Baz")
    assert_equal [], database.references("::Foo#bar").select { _1.path == Pathname("lib/a.rb") }
  end

  def test_location
    database = TypeCheckDatabase.new()

    database.update_rbs(path: Pathname("sig/a.rbs"), target: :app, entries: [entry("::Foo", role: :definition, at: [1, 2, 3, 4])])

    location = database.definitions("::Foo")[0] || raise
    assert_equal Pathname("sig/a.rbs"), location.path
    assert_equal :rbs, location.source
    assert_equal({ start: { line: 1, character: 2 }, end: { line: 3, character: 4 } }, location.lsp_range)
  end

  def test_inline_file_has_entries_in_sources_and_rbs
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )
    database.update_rbs(path: path, target: :app, entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])

    # The same range is reported twice, as Ruby code and as an inline declaration
    assert_equal [[path, :ruby, 0], [path, :rbs, 0]], summarize(database.definitions("::Foo"))
  end

  def test_rbs_merge_targets
    database = TypeCheckDatabase.new()

    path = Pathname("sig/a.rbs")
    database.update_rbs(
      path: path,
      target: :app,
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Bar", role: :reference, at: [1, 12, 1, 15])
      ]
    )
    database.update_rbs(
      path: path,
      target: :test,
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Test::Bar", role: :reference, at: [1, 12, 1, 15])
      ]
    )

    # The definition is deduplicated, and the references resolved differently in the targets are both returned
    assert_equal [[path, :rbs, 0]], summarize(database.definitions("::Foo"))
    assert_equal [[path, :rbs, 1]], summarize(database.references("::Bar"))
    assert_equal [[path, :rbs, 1]], summarize(database.references("::Test::Bar"))
    assert_equal 4, database.entry_count
  end

  def test_update_replaces_previous_result
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [diagnostic("a")],
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Bar", role: :definition, at: [5, 6, 5, 9])
      ]
    )
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Bar", role: :definition, at: [3, 6, 3, 9])
      ]
    )

    assert_equal [], database.diagnostics(path)
    assert_equal [], database.definitions("::Foo")
    assert_equal [[path, :ruby, 3]], summarize(database.definitions("::Bar"))
    assert_equal 1, database.entry_count
    assert_equal 1, database.pool.size
  end

  def test_update_signature_replaces_only_the_target
    database = TypeCheckDatabase.new()

    path = Pathname("sig/a.rbs")
    database.update_signature(path: path, target: :app, diagnostics: [diagnostic("app")])
    database.update_signature(path: path, target: :test, diagnostics: [diagnostic("test")])

    database.update_signature(path: path, target: :app, diagnostics: [])
    assert_equal ["test"], database.diagnostics(path).map { _1[:message] }

    # Skipping the validation keeps the diagnostics of the target
    database.update_signature(path: path, target: :test, diagnostics: nil)
    assert_equal ["test"], database.diagnostics(path).map { _1[:message] }
  end

  def test_update_rbs_replaces_only_the_target
    database = TypeCheckDatabase.new()

    path = Pathname("sig/a.rbs")
    database.update_rbs(path: path, target: :app, entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])
    database.update_rbs(path: path, target: :test, entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])

    database.update_rbs(path: path, target: :app, entries: [])
    assert_equal [[path, :rbs, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.entry_count

    # `nil` keeps the entries, for the signatures that fail to load
    database.update_rbs(path: path, target: :test, entries: nil)
    assert_equal [[path, :rbs, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.pool.size
  end

  def test_remove_releases_everything
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [diagnostic("a")],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )
    database.update_signature(path: path, target: :app, diagnostics: [diagnostic("b")])
    database.update_signature(path: path, target: :test, diagnostics: [diagnostic("c")])
    database.update_rbs(path: path, target: :app, entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])
    database.update_rbs(path: path, target: :test, entries: [entry("::Foo", role: :reference, at: [1, 0, 1, 3])])

    database.remove(path)

    assert_equal [], database.diagnostics(path)
    assert_equal [], database.definitions("::Foo")
    assert_equal [], database.references("::Foo")
    assert_equal 0, database.entry_count
    assert_equal 0, database.pool.size
  end

  def test_name_shared_between_files_survives_removal_of_one
    database = TypeCheckDatabase.new()

    database.update_source(
      path: Pathname("lib/a.rb"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )
    database.update_rbs(path: Pathname("sig/a.rbs"), target: :app, entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])

    database.remove(Pathname("sig/a.rbs"))

    assert_equal [[Pathname("lib/a.rb"), :ruby, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.pool.size
  end

  def test_entry_wire_round_trip
    e = entry("::Foo#bar", role: :reference, at: [1, 2, 3, 4])

    assert_equal ["::Foo#bar", 1, 1, 2, 3, 4], e.to_wire
    assert_equal e, TypeCheckDatabase::Entry.from_wire(e.to_wire)

    # The kind of a definition is in the code with the role
    e = entry("::Foo#bar", role: :definition, kind: :method, at: [1, 2, 3, 4])

    assert_equal ["::Foo#bar", 14, 1, 2, 3, 4], e.to_wire
    assert_equal e, TypeCheckDatabase::Entry.from_wire(e.to_wire)

    TypeCheckDatabase::KIND_CODES.each_key do |kind|
      e = entry("::Foo", role: :definition, kind: kind, at: [1, 2, 3, 4])
      assert_equal e, TypeCheckDatabase::Entry.from_wire(e.to_wire)
    end
  end

  def test_definitions_with_kinds
    database = TypeCheckDatabase.new()

    database.update_rbs(
      path: Pathname("sig/foo.rbs"),
      target: :app,
      entries: [
        entry("::Foo", role: :definition, kind: :class, at: [0, 6, 0, 9]),
        entry("::Foo", role: :reference, at: [1, 10, 1, 13])
      ]
    )

    # The kind doesn't change the role of the entry
    assert_equal [0], database.definitions("::Foo").map(&:start_line)
    assert_equal [1], database.references("::Foo").map(&:start_line)
  end

  def test_rbs_definitions
    database = TypeCheckDatabase.new()

    database.update_rbs(
      path: Pathname("sig/foo.rbs"),
      target: :app,
      entries: [
        entry("::Foo", role: :definition, kind: :class, at: [0, 6, 0, 9]),
        entry("::Foo#bar", role: :definition, kind: :method, at: [1, 6, 1, 9]),
        entry("::Foo#name", role: :definition, kind: :attribute, at: [2, 16, 2, 20]),
        entry("::Bar", role: :reference, at: [1, 13, 1, 16])
      ]
    )
    database.update_rbs(
      path: Pathname("sig/bar.rbs"),
      target: :app,
      entries: [
        entry("::Bar", role: :definition, kind: :module, at: [0, 7, 0, 10]),
        entry("$FOOBAR", role: :definition, kind: :global, at: [2, 0, 2, 7])
      ]
    )
    # The definitions in Ruby code have no kind, and are not RBS declarations
    database.update_source(
      path: Pathname("lib/foo.rb"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo#bar", role: :definition, at: [1, 6, 1, 9])]
    )

    summary = -> (definitions) { definitions.map { [_1.name, _1.kind, _1.location.path, _1.location.start_line] }.sort }

    # Every declaration for the empty query, without the references
    assert_equal(
      [
        ["$FOOBAR", :global, Pathname("sig/bar.rbs"), 2],
        ["::Bar", :module, Pathname("sig/bar.rbs"), 0],
        ["::Foo", :class, Pathname("sig/foo.rbs"), 0],
        ["::Foo#bar", :method, Pathname("sig/foo.rbs"), 1],
        ["::Foo#name", :attribute, Pathname("sig/foo.rbs"), 2]
      ],
      summary[database.rbs_definitions("")]
    )

    # The fully qualified names including the query, ignoring the case
    assert_equal(
      [
        ["$FOOBAR", :global, Pathname("sig/bar.rbs"), 2],
        ["::Foo", :class, Pathname("sig/foo.rbs"), 0],
        ["::Foo#bar", :method, Pathname("sig/foo.rbs"), 1],
        ["::Foo#name", :attribute, Pathname("sig/foo.rbs"), 2]
      ],
      summary[database.rbs_definitions("foo")]
    )
    assert_equal(
      [
        ["$FOOBAR", :global, Pathname("sig/bar.rbs"), 2],
        ["::Bar", :module, Pathname("sig/bar.rbs"), 0],
        ["::Foo#bar", :method, Pathname("sig/foo.rbs"), 1]
      ],
      summary[database.rbs_definitions("BAR")]
    )
    assert_equal [], database.rbs_definitions("baz")

    location = database.rbs_definitions("#name")[0]&.location or raise
    assert_equal :rbs, location.source
    assert_equal({ start: { line: 2, character: 16 }, end: { line: 2, character: 20 } }, location.lsp_range)
  end

  def test_rbs_definitions_merge_targets
    database = TypeCheckDatabase.new()

    path = Pathname("/gems/core/string.rbs")
    [:app, :test].each do |target|
      database.update_rbs(path: path, target: target, entries: [entry("::String", role: :definition, kind: :class, at: [0, 6, 0, 12])])
    end

    # The same entries in the targets are returned once
    assert_equal [0], database.rbs_definitions("String").map { _1.location.start_line }
    assert_equal [0], database.rbs_definitions("").map { _1.location.start_line }

    database.update_rbs(
      path: path,
      target: :test,
      entries: [
        entry("::String", role: :definition, kind: :class, at: [0, 6, 0, 12]),
        entry("::String", role: :definition, kind: :class, at: [5, 6, 5, 12])
      ]
    )

    # The entries of the targets are merged when they differ
    assert_equal [0, 5], database.rbs_definitions("String").map { _1.location.start_line }.sort
    assert_equal [0, 5], database.rbs_definitions("").map { _1.location.start_line }.sort
  end

  def test_stats_follow_diagnostics
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(path: path, target: :app, diagnostics: [], entries: [], stats: { typed_calls: 2, untyped_calls: 1, error_calls: 0 })

    result = database.each_source.to_a.fetch(0)
    assert_equal path, result[0]
    assert_equal :app, result[1].target
    assert_equal({ typed_calls: 2, untyped_calls: 1, error_calls: 0 }, result[1].stats)

    # Skipping the type checking keeps the stats
    database.update_source(path: path, target: :app, diagnostics: nil, entries: nil)
    assert_equal({ typed_calls: 2, untyped_calls: 1, error_calls: 0 }, database.each_source.to_a.fetch(0)[1].stats)

    # A type checking without a Typing has no stats
    database.update_source(path: path, target: :app, diagnostics: [diagnostic("syntax error")], entries: nil, stats: nil)
    assert_nil database.each_source.to_a.fetch(0)[1].stats
  end

  def test_checked_and_paths
    database = TypeCheckDatabase.new()

    refute_operator database, :checked?, Pathname("lib/a.rb")
    assert_equal [], database.paths

    database.update_source(path: Pathname("lib/a.rb"), target: :app, diagnostics: [], entries: [])
    database.update_signature(path: Pathname("lib/a.rb"), target: :app, diagnostics: [])
    database.update_signature(path: Pathname("sig/a.rbs"), target: :app, diagnostics: [])

    # The indexed files are not checked
    database.update_rbs(path: Pathname("sig/b.rbs"), target: :app, entries: [])
    refute_operator database, :checked?, Pathname("sig/b.rbs")

    assert_operator database, :checked?, Pathname("lib/a.rb")
    assert_operator database, :checked?, Pathname("sig/a.rbs")
    assert_equal [Pathname("lib/a.rb"), Pathname("sig/a.rbs")], database.paths
    assert_equal [Pathname("lib/a.rb")], database.each_source.map { |path, _| path }

    database.remove(Pathname("lib/a.rb"))
    refute_operator database, :checked?, Pathname("lib/a.rb")
    assert_equal [Pathname("sig/a.rbs")], database.paths
  end

  def test_rbs_declarations
    database = TypeCheckDatabase.new()

    path = Pathname("sig/foo.rbs")
    database.update_rbs(
      path: path,
      target: :app,
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Foo#bar", role: :definition, at: [1, 6, 1, 9]),
        entry("::Foo.baz", role: :definition, at: [2, 11, 2, 14]),
        entry("::_Foo", role: :definition, at: [4, 10, 4, 14]),
        entry("::foo", role: :definition, at: [7, 5, 7, 8]),
        entry("$foo", role: :definition, at: [9, 0, 9, 4])
      ]
    )

    assert_equal [0], database.definitions("::Foo").map(&:start_line)
    assert_equal [1], database.definitions("::Foo#bar").map(&:start_line)
    assert_equal [2], database.definitions("::Foo.baz").map(&:start_line)
    assert_equal [4], database.definitions("::_Foo").map(&:start_line)
    assert_equal [7], database.definitions("::foo").map(&:start_line)
    assert_equal [9], database.definitions("$foo").map(&:start_line)
    assert_equal 6, database.entry_count
  end

  def test_rbs_entries_by_path
    env = RBS::Environment.new

    buffer = RBS::Buffer.new(name: Pathname("sig/foo.rbs"), content: <<~RBS)
      class Foo[T < Bar] < Bar
        include Mixin[Qux]
        def bar: (Qux) -> Bar
        attr_accessor baz: Qux
        alias bar2 bar
        @ivar: Qux
      end

      module Mixin[T] : Bar
      end

      interface _Foo
        def foo: () -> Qux
      end

      type foo = Qux | Bar

      FOO: Qux

      $foo: Qux

      class Alias = Foo

      class Bar
      end

      class Qux
      end

      module MixinAlias = Mixin
    RBS
    _, directives, declarations = RBS::Parser.parse_signature(buffer)
    env.add_source(RBS::Source::RBS.new(buffer, directives, declarations))

    entries = TypeCheckDatabase.rbs_entries_by_path(env.resolve_type_names).fetch(Pathname("sig/foo.rbs")).map { [_1.name, _1.kind || _1.role, _1.start_line, _1.start_character, _1.end_line, _1.end_character] }

    # Declarations, at the names
    assert_includes entries, ["::Foo", :class, 0, 6, 0, 9]
    assert_includes entries, ["::Foo#bar", :method, 2, 6, 2, 9]
    assert_includes entries, ["::Foo#baz", :attribute, 3, 16, 3, 19]
    assert_includes entries, ["::Foo#baz=", :attribute, 3, 16, 3, 19]
    assert_includes entries, ["::Foo#bar2", :method, 4, 8, 4, 12]
    assert_includes entries, ["::Mixin", :module, 8, 7, 8, 12]
    assert_includes entries, ["::_Foo", :interface, 11, 10, 11, 14]
    assert_includes entries, ["::_Foo#foo", :method, 12, 6, 12, 9]
    assert_includes entries, ["::foo", :type_alias, 15, 5, 15, 8]
    assert_includes entries, ["::FOO", :constant, 17, 0, 17, 3]
    assert_includes entries, ["$foo", :global, 19, 0, 19, 4]
    assert_includes entries, ["::Alias", :class, 21, 6, 21, 11]
    assert_includes entries, ["::MixinAlias", :module, 29, 7, 29, 17]

    # References, at the type names
    assert_includes entries, ["::Bar", :reference, 0, 14, 0, 17]      # Upper bound of the type parameter
    assert_includes entries, ["::Bar", :reference, 0, 21, 0, 24]      # Super class
    assert_includes entries, ["::Mixin", :reference, 1, 10, 1, 15]    # Mixin
    assert_includes entries, ["::Qux", :reference, 1, 16, 1, 19]      # Type argument of the mixin
    assert_includes entries, ["::Qux", :reference, 2, 12, 2, 15]      # Parameter type
    assert_includes entries, ["::Bar", :reference, 2, 20, 2, 23]      # Return type
    assert_includes entries, ["::Qux", :reference, 3, 21, 3, 24]      # Attribute type
    assert_includes entries, ["::Foo#bar", :reference, 4, 13, 4, 16]  # Old name of the alias
    assert_includes entries, ["::Qux", :reference, 5, 9, 5, 12]       # Instance variable type
    assert_includes entries, ["::Bar", :reference, 8, 18, 8, 21]      # Module self type
    assert_includes entries, ["::Qux", :reference, 12, 17, 12, 20]    # Return type of the interface method
    assert_includes entries, ["::Qux", :reference, 15, 11, 15, 14]    # Type alias
    assert_includes entries, ["::Bar", :reference, 15, 17, 15, 20]
    assert_includes entries, ["::Qux", :reference, 17, 5, 17, 8]      # Constant type
    assert_includes entries, ["::Qux", :reference, 19, 6, 19, 9]      # Global type
    assert_includes entries, ["::Foo", :reference, 21, 14, 21, 17]    # Class alias target
    assert_includes entries, ["::Mixin", :reference, 29, 20, 29, 25]  # Module alias target

    # Each entry is included once
    assert_equal entries.uniq, entries
  end

  def test_rbs_entries_by_path_inline
    env = RBS::Environment.new

    buffer = RBS::Buffer.new(name: Pathname("lib/foo.rb"), content: <<~RUBY)
      class Foo < Bar #[Qux]
        include Mixin #[Qux]

        # @rbs (Qux) -> Bar
        def foo(x)
        end
      end

      class Bar
      end

      class Qux
      end

      module Mixin
      end

      QuxAlias = Qux #: class-alias
      MixinAlias = Mixin #: module-alias
    RUBY
    prism = Prism.parse(buffer.content)
    result = RBS::InlineParser.parse(buffer, prism)
    env.add_source(RBS::Source::Ruby.new(buffer, prism, result.declarations, result.diagnostics))

    entries = TypeCheckDatabase.rbs_entries_by_path(env.resolve_type_names).fetch(Pathname("lib/foo.rb")).map { [_1.name, _1.kind || _1.role, _1.start_line, _1.start_character, _1.end_line, _1.end_character] }

    # Declarations, at the names in the Ruby file
    assert_includes entries, ["::Foo", :class, 0, 6, 0, 9]
    assert_includes entries, ["::Foo#foo", :method, 4, 6, 4, 9]
    assert_includes entries, ["::Bar", :class, 8, 6, 8, 9]
    assert_includes entries, ["::QuxAlias", :class, 17, 0, 17, 8]
    assert_includes entries, ["::MixinAlias", :module, 18, 0, 18, 10]

    # References, at the type names in the Ruby file
    assert_includes entries, ["::Bar", :reference, 0, 12, 0, 15]    # Super class
    assert_includes entries, ["::Qux", :reference, 0, 18, 0, 21]    # Type argument of the super class
    assert_includes entries, ["::Mixin", :reference, 1, 10, 1, 15]  # Mixin
    assert_includes entries, ["::Qux", :reference, 1, 18, 1, 21]    # Type argument of the mixin
    assert_includes entries, ["::Qux", :reference, 3, 10, 3, 13]    # Parameter type in the annotation
    assert_includes entries, ["::Bar", :reference, 3, 18, 3, 21]    # Return type in the annotation
  end

  def test_library_entries
    database = TypeCheckDatabase.new()

    path = Pathname("/gems/core/string.rbs")
    database.update_rbs(
      path: path,
      target: :app,
      entries: [
        entry("::String", role: :definition, at: [0, 6, 0, 12]),
        entry("::Integer", role: :reference, at: [3, 20, 3, 27])
      ]
    )
    database.update_source(path: Pathname("lib/a.rb"), target: :app, diagnostics: [], entries: [entry("::String", role: :reference, at: [1, 0, 1, 6])])

    assert_equal [[path, :rbs, 0]], summarize(database.definitions("::String"))
    assert_equal [[Pathname("lib/a.rb"), :ruby, 1]], summarize(database.references("::String"))
    assert_equal [[path, :rbs, 3]], summarize(database.references("::Integer"))
    assert_equal 3, database.entry_count

    # Indexed library files are not validated: they are not `checked?`, not in `paths`, and have no diagnostics
    refute database.checked?(path)
    assert_equal [Pathname("lib/a.rb")], database.paths
    assert_equal [], database.diagnostics(path)

    # Updating replaces the entries of the file
    database.update_rbs(path: path, target: :app, entries: [entry("::String", role: :definition, at: [1, 6, 1, 12])])
    assert_equal [[path, :rbs, 1]], summarize(database.definitions("::String"))
    assert_equal [], database.references("::Integer")
    assert_equal 2, database.entry_count

    database.remove(path)
    assert_equal [], database.definitions("::String")
    assert_equal 1, database.entry_count
  end
end
