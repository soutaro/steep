require_relative "../test_helper"

class Steep::Server::TypeCheckDatabaseTest < Minitest::Test
  include TestHelper

  include Steep

  # @rbs skip
  TypeCheckDatabase = Server::TypeCheckDatabase

  # @rbs!
  #   class TypeCheckDatabase = Steep::Server::TypeCheckDatabase

  def entry(name, role:, at:) #: TypeCheckDatabase::Entry
    start_line, start_character, end_line, end_character = at
    TypeCheckDatabase::Entry.new(
      name: name,
      role: role,
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
    database.update_signature(path: path, target: :app, diagnostics: [shared, diagnostic("app only")], entries: [])
    database.update_signature(path: path, target: :test, diagnostics: [shared, diagnostic("test only")], entries: [])

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

    database.update_signature(
      path: Pathname("sig/a.rbs"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [1, 2, 3, 4])]
    )

    location = database.definitions("::Foo")[0] || raise
    assert_equal Pathname("sig/a.rbs"), location.path
    assert_equal :rbs, location.source
    assert_equal({ start: { line: 1, character: 2 }, end: { line: 3, character: 4 } }, location.lsp_range)
  end

  def test_inline_file_has_results_in_both_tables
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update_source(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )
    database.update_signature(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )

    # The same range is reported twice, as Ruby code and as an inline declaration
    assert_equal [[path, :ruby, 0], [path, :rbs, 0]], summarize(database.definitions("::Foo"))
  end

  def test_signatures_merge_targets
    database = TypeCheckDatabase.new()

    path = Pathname("sig/a.rbs")
    database.update_signature(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", role: :definition, at: [0, 6, 0, 9]),
        entry("::Bar", role: :reference, at: [1, 12, 1, 15])
      ]
    )
    database.update_signature(
      path: path,
      target: :test,
      diagnostics: [],
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
    database.update_signature(path: path, target: :app, diagnostics: [diagnostic("app")], entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])
    database.update_signature(path: path, target: :test, diagnostics: [diagnostic("test")], entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])])

    database.update_signature(path: path, target: :app, diagnostics: [], entries: [])

    assert_equal ["test"], database.diagnostics(path).map { _1[:message] }
    assert_equal [[path, :rbs, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.entry_count
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
    database.update_signature(
      path: path,
      target: :app,
      diagnostics: [diagnostic("b")],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )
    database.update_signature(
      path: path,
      target: :test,
      diagnostics: [diagnostic("c")],
      entries: [entry("::Foo", role: :reference, at: [1, 0, 1, 3])]
    )

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
    database.update_signature(
      path: Pathname("sig/a.rbs"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", role: :definition, at: [0, 6, 0, 9])]
    )

    database.remove(Pathname("sig/a.rbs"))

    assert_equal [[Pathname("lib/a.rb"), :ruby, 0]], summarize(database.definitions("::Foo"))
    assert_equal 1, database.pool.size
  end

  def test_entry_wire_round_trip
    e = entry("::Foo#bar", role: :reference, at: [1, 2, 3, 4])

    assert_equal ["::Foo#bar", 1, 1, 2, 3, 4], e.to_wire
    assert_equal e, TypeCheckDatabase::Entry.from_wire(e.to_wire)
  end

  def test_rbs_declarations
    database = TypeCheckDatabase.new()

    path = Pathname("sig/foo.rbs")
    database.update_signature(
      path: path,
      target: :app,
      diagnostics: [],
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
end
