require_relative "../test_helper"

class Steep::Server::TypeCheckDatabaseTest < Minitest::Test
  include TestHelper

  include Steep

  # @rbs skip
  TypeCheckDatabase = Server::TypeCheckDatabase

  # @rbs!
  #   class TypeCheckDatabase = Steep::Server::TypeCheckDatabase

  def entry(name, kind:, role:, source: :ruby, at:) #: TypeCheckDatabase::Entry
    start_line, start_character, end_line, end_character = at
    TypeCheckDatabase::Entry.new(
      name: name,
      kind: kind,
      role: role,
      source: source,
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

  def test_diagnostics_of_merges_targets
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    shared = diagnostic("shared")

    database.update(path: path, target: :app, diagnostics: [shared, diagnostic("app only")], entries: [])
    database.update(path: path, target: :test, diagnostics: [shared, diagnostic("test only")], entries: [])

    diagnostics = database.diagnostics_of(path) || raise
    assert_equal 3, diagnostics.size
    assert_equal ["shared", "app only", "test only"], diagnostics.map { _1[:message] }
  end

  def test_diagnostics_of_unchecked_file
    database = TypeCheckDatabase.new()

    assert_nil database.diagnostics_of(Pathname("lib/a.rb"))
    refute_operator database, :checked?, Pathname("lib/a.rb")
  end

  def test_diagnostics_of_skipped_type_check
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update(path: path, target: :app, diagnostics: nil, entries: [])

    assert_nil database.diagnostics_of(path)
    assert_operator database, :checked?, path

    database.update(path: path, target: :test, diagnostics: [], entries: [])

    assert_equal [], database.diagnostics_of(path)
  end

  def test_each_diagnostics
    database = TypeCheckDatabase.new()

    database.update(path: Pathname("lib/a.rb"), target: :app, diagnostics: [diagnostic("a")], entries: [])
    database.update(path: Pathname("lib/b.rb"), target: :app, diagnostics: nil, entries: [])

    pairs = database.each_diagnostics.to_a
    assert_equal [Pathname("lib/a.rb")], pairs.map(&:first)
  end

  def test_definitions_and_references
    database = TypeCheckDatabase.new()

    database.update(
      path: Pathname("lib/a.rb"),
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", kind: :constant, role: :definition, at: [0, 6, 0, 9]),
        entry("::Foo#bar", kind: :method, role: :definition, at: [1, 6, 1, 9])
      ]
    )
    database.update(
      path: Pathname("lib/b.rb"),
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", kind: :constant, role: :reference, at: [3, 0, 3, 3]),
        entry("::Foo#bar", kind: :method, role: :reference, at: [3, 4, 3, 7])
      ]
    )

    definitions = database.definitions(name: "::Foo#bar")
    assert_equal [[Pathname("lib/a.rb"), 1]], definitions.map { |path, entry| [path, entry.start_line] }

    references = database.references(name: "::Foo")
    assert_equal [[Pathname("lib/b.rb"), 3]], references.map { |path, entry| [path, entry.start_line] }

    assert_equal [], database.definitions(name: "::Foo", kind: :method)
    assert_equal 1, database.definitions(name: "::Foo", kind: :constant).size

    assert_equal [], database.definitions(name: "::Baz")
  end

  def test_update_replaces_previous_result
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", kind: :constant, role: :definition, at: [0, 6, 0, 9]),
        entry("::Bar", kind: :constant, role: :definition, at: [5, 6, 5, 9])
      ]
    )
    database.update(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Bar", kind: :constant, role: :definition, at: [3, 6, 3, 9])
      ]
    )

    assert_equal [], database.definitions(name: "::Foo")
    assert_equal [3], database.definitions(name: "::Bar").map { |_, entry| entry.start_line }
    assert_equal 1, database.entry_count
    assert_equal 1, database.pool.size
  end

  def test_remove_releases_everything
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    database.update(
      path: path,
      target: :app,
      diagnostics: [diagnostic("a")],
      entries: [entry("::Foo", kind: :constant, role: :definition, at: [0, 6, 0, 9])]
    )
    database.update(
      path: path,
      target: :test,
      diagnostics: [diagnostic("b")],
      entries: [entry("::Foo", kind: :constant, role: :reference, at: [1, 0, 1, 3])]
    )

    database.remove(path)

    refute_operator database, :checked?, path
    assert_nil database.diagnostics_of(path)
    assert_equal [], database.definitions(name: "::Foo")
    assert_equal 0, database.entry_count
    assert_equal 0, database.pool.size
  end

  def test_name_shared_between_files_survives_removal_of_one
    database = TypeCheckDatabase.new()

    database.update(
      path: Pathname("lib/a.rb"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", kind: :constant, role: :definition, at: [0, 6, 0, 9])]
    )
    database.update(
      path: Pathname("lib/b.rb"),
      target: :app,
      diagnostics: [],
      entries: [entry("::Foo", kind: :constant, role: :reference, at: [1, 0, 1, 3])]
    )

    database.remove(Pathname("lib/b.rb"))

    assert_equal 1, database.definitions(name: "::Foo").size
    assert_equal 1, database.pool.size
  end

  def test_references_deduplicates_targets
    database = TypeCheckDatabase.new()

    path = Pathname("lib/a.rb")
    [:app, :test].each do |target|
      database.update(
        path: path,
        target: target,
        diagnostics: [],
        entries: [entry("::Foo", kind: :constant, role: :reference, at: [0, 0, 0, 3])]
      )
    end

    assert_equal 1, database.references(name: "::Foo").size
  end

  def test_rbs_declarations
    database = TypeCheckDatabase.new()

    path = Pathname("sig/foo.rbs")
    database.update(
      path: path,
      target: :app,
      diagnostics: [],
      entries: [
        entry("::Foo", kind: :constant, role: :definition, source: :rbs, at: [0, 6, 0, 9]),
        entry("::Foo#bar", kind: :method, role: :definition, source: :rbs, at: [1, 6, 1, 9]),
        entry("::_Foo", kind: :interface, role: :definition, source: :rbs, at: [4, 10, 4, 14]),
        entry("::foo", kind: :type_alias, role: :definition, source: :rbs, at: [7, 5, 7, 8]),
        entry("$foo", kind: :global, role: :definition, source: :rbs, at: [9, 0, 9, 4])
      ]
    )

    assert_equal [:rbs], database.definitions(name: "::Foo").map { |_, entry| entry.source }
    assert_equal 1, database.definitions(name: "::_Foo", kind: :interface).size
    assert_equal [], database.definitions(name: "::_Foo", kind: :constant)
    assert_equal 1, database.definitions(name: "::foo", kind: :type_alias).size
    assert_equal 1, database.definitions(name: "$foo", kind: :global).size
    assert_equal 5, database.entry_count
  end

  def test_entry_lsp_range
    e = entry("::Foo", kind: :constant, role: :definition, at: [1, 2, 3, 4])

    assert_equal({ start: { line: 1, character: 2 }, end: { line: 3, character: 4 } }, e.lsp_range)
  end

  def test_entry_wire_round_trip
    e = entry("::Foo#bar", kind: :method, role: :reference, at: [1, 2, 3, 4])

    assert_equal ["::Foo#bar", 1, 1, 0, 1, 2, 3, 4], e.to_wire
    assert_equal e, TypeCheckDatabase::Entry.from_wire(e.to_wire)
  end
end
