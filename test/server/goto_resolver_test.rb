require_relative "../test_helper"

class Steep::Server::GotoResolverTest < Minitest::Test
  include TestHelper

  include Steep

  # @rbs skip
  TypeCheckDatabase = Server::TypeCheckDatabase
  # @rbs skip
  GotoResolver = Server::GotoResolver

  # @rbs!
  #   class TypeCheckDatabase = Steep::Server::TypeCheckDatabase
  #   class GotoResolver = Steep::Server::GotoResolver

  RUBY_PATH = Pathname("/app/lib/customer.rb")
  RBS_PATH = Pathname("/app/sig/customer.rbs")

  def entry(name, kind:, source:, at:) #: TypeCheckDatabase::Entry
    start_line, start_character, end_line, end_character = at
    TypeCheckDatabase::Entry.new(
      name: name,
      kind: kind,
      role: :definition,
      source: source,
      start_line: start_line,
      start_character: start_character,
      end_line: end_line,
      end_character: end_character
    )
  end

  def database #: TypeCheckDatabase
    @database ||= TypeCheckDatabase.new().tap do |database|
      database.update(
        path: RUBY_PATH,
        target: :app,
        diagnostics: [],
        entries: [
          entry("::Customer", kind: :constant, source: :ruby, at: [0, 6, 0, 14]),
          entry("::Customer#initialize", kind: :method, source: :ruby, at: [1, 6, 1, 16]),
          entry("::Customer#name", kind: :method, source: :ruby, at: [4, 6, 4, 10])
        ]
      )
      database.update(
        path: RBS_PATH,
        target: :app,
        diagnostics: [],
        entries: [
          entry("::Customer", kind: :constant, source: :rbs, at: [0, 6, 0, 14]),
          entry("::Customer#initialize", kind: :method, source: :rbs, at: [1, 6, 1, 16]),
          entry("::Customer#name", kind: :method, source: :rbs, at: [2, 6, 2, 10]),
          entry("::_Greeter", kind: :interface, source: :rbs, at: [5, 10, 5, 18]),
          entry("::greeting", kind: :type_alias, source: :rbs, at: [8, 5, 8, 13])
        ]
      )
    end
  end

  def resolver #: GotoResolver
    GotoResolver.new(database: database)
  end

  def uri(path) #: String
    PathHelper.to_uri(path).to_s
  end

  # Returns `[uri, start line]` pairs of the locations
  def summarize(locations) #: Array[[String, Integer]]
    locations.map { |location| [location[:uri], location[:range][:start][:line]] }
  end

  def test_definition_from_ruby_jumps_to_rbs
    locations = resolver.goto(
      kind: :definition,
      symbols: [
        { name: "::Customer#name", kind: "method", from: "ruby" },
        { name: "::Customer", kind: "constant", from: "ruby" }
      ]
    )

    assert_equal [[uri(RBS_PATH), 2], [uri(RBS_PATH), 0]], summarize(locations)
    assert_equal({ start: { line: 2, character: 6 }, end: { line: 2, character: 10 } }, locations[0][:range])
  end

  def test_definition_from_rbs_jumps_to_ruby
    locations = resolver.goto(
      kind: :definition,
      symbols: [
        { name: "::Customer#name", kind: "method", from: "rbs" },
        { name: "::Customer", kind: "constant", from: "rbs" }
      ]
    )

    assert_equal [[uri(RUBY_PATH), 4], [uri(RUBY_PATH), 0]], summarize(locations)
  end

  def test_implementation_jumps_to_ruby
    locations = resolver.goto(
      kind: :implementation,
      symbols: [
        { name: "::Customer#name", kind: "method", from: "ruby" },
        { name: "::Customer", kind: "constant", from: "ruby" },
        { name: "::Customer", kind: "type_name", from: nil }
      ]
    )

    # The constant and the type name resolve to the same location
    assert_equal [[uri(RUBY_PATH), 4], [uri(RUBY_PATH), 0]], summarize(locations)
  end

  def test_new_falls_back_to_initialize
    locations = resolver.goto(kind: :definition, symbols: [{ name: "::Customer.new", kind: "method", from: "ruby" }])
    assert_equal [[uri(RBS_PATH), 1]], summarize(locations)

    locations = resolver.goto(kind: :implementation, symbols: [{ name: "::Customer.new", kind: "method", from: "ruby" }])
    assert_equal [[uri(RUBY_PATH), 1]], summarize(locations)
  end

  def test_type_definition_jumps_to_rbs_declarations
    locations = resolver.goto(
      kind: :type_definition,
      symbols: [
        { name: "::_Greeter", kind: "type_name", from: nil },
        { name: "::greeting", kind: "type_name", from: nil },
        { name: "::Customer", kind: "type_name", from: nil }
      ]
    )

    assert_equal [[uri(RBS_PATH), 5], [uri(RBS_PATH), 8], [uri(RBS_PATH), 0]], summarize(locations)
  end

  def test_unknown_symbol
    assert_equal [], resolver.goto(kind: :definition, symbols: [{ name: "::Nothing", kind: "constant", from: "ruby" }])
  end

  def test_query_definition_method
    result = resolver.query_definition("Customer#name")

    assert_equal "Customer#name", result[:name]
    assert_equal "instance_method", result[:kind]
    assert_equal(
      [[uri(RUBY_PATH), 4, "ruby"], [uri(RBS_PATH), 2, "rbs"]],
      result[:locations].map { |location| [location[:uri], location[:range][:start][:line], location[:source]] }
    )
  end

  def test_query_definition_new
    result = resolver.query_definition("Customer.new")

    assert_equal "singleton_method", result[:kind]
    assert_equal [[uri(RUBY_PATH), 1], [uri(RBS_PATH), 1]], summarize(result[:locations])
  end

  def test_query_definition_type_name
    result = resolver.query_definition("Customer")
    assert_equal "type_name", result[:kind]
    assert_equal [[uri(RUBY_PATH), 0], [uri(RBS_PATH), 0]], summarize(result[:locations])

    result = resolver.query_definition("_Greeter")
    assert_equal "type_name", result[:kind]
    assert_equal [[uri(RBS_PATH), 5]], summarize(result[:locations])

    result = resolver.query_definition("greeting")
    assert_equal "type_name", result[:kind]
    assert_equal [[uri(RBS_PATH), 8]], summarize(result[:locations])
  end

  def test_query_definition_unknown
    # A method name without the method part cannot be parsed
    result = resolver.query_definition("Customer#")

    assert_equal "unknown", result[:kind]
    assert_equal [], result[:locations]

    # A type name that is declared nowhere
    result = resolver.query_definition("Nothing")

    assert_equal "type_name", result[:kind]
    assert_equal [], result[:locations]
  end
end
