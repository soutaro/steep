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

  def entry(name, at:) #: TypeCheckDatabase::Entry
    start_line, start_character, end_line, end_character = at
    TypeCheckDatabase::Entry.new(
      name: name,
      role: :definition,
      start_line: start_line,
      start_character: start_character,
      end_line: end_line,
      end_character: end_character
    )
  end

  def database #: TypeCheckDatabase
    @database ||= TypeCheckDatabase.new().tap do |database|
      database.update_source(
        path: RUBY_PATH,
        target: :app,
        diagnostics: [],
        entries: [
          entry("::Customer", at: [0, 6, 0, 14]),
          entry("::Customer#initialize", at: [1, 6, 1, 16]),
          entry("::Customer#name", at: [4, 6, 4, 10])
        ]
      )
      database.update_signature(
        path: RBS_PATH,
        target: :app,
        diagnostics: [],
        entries: [
          entry("::Customer", at: [0, 6, 0, 14]),
          entry("::Customer#initialize", at: [1, 6, 1, 16]),
          entry("::Customer#name", at: [2, 6, 2, 10]),
          entry("::_Greeter", at: [5, 10, 5, 18]),
          entry("::greeting", at: [8, 5, 8, 13])
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

  def result(constant: nil, type_name: nil, method_names: nil, type: nil) #: Steep::Server::CustomMethods::Source__Symbol::result
    result = {} #: Steep::Server::CustomMethods::Source__Symbol::result
    result[:constant] = constant if constant
    result[:type_name] = type_name if type_name
    result[:method_names] = method_names if method_names
    result[:type] = type if type
    result
  end

  def test_definition_from_ruby_jumps_to_rbs
    locations = resolver.goto(kind: :definition, from: :ruby, result: result(constant: "::Customer", method_names: ["::Customer#name"]))

    assert_equal [[uri(RBS_PATH), 0], [uri(RBS_PATH), 2]], summarize(locations)
    assert_equal({ start: { line: 2, character: 6 }, end: { line: 2, character: 10 } }, locations[1][:range])
  end

  def test_definition_from_rbs_jumps_to_ruby
    locations = resolver.goto(kind: :definition, from: :rbs, result: result(constant: "::Customer", method_names: ["::Customer#name"]))

    assert_equal [[uri(RUBY_PATH), 0], [uri(RUBY_PATH), 4]], summarize(locations)
  end

  def test_definition_of_type_name_jumps_to_rbs
    # A type name written in a type goes to its RBS declaration, whichever side the cursor is on
    locations = resolver.goto(kind: :definition, from: :ruby, result: result(type_name: "::_Greeter"))
    assert_equal [[uri(RBS_PATH), 5]], summarize(locations)

    locations = resolver.goto(kind: :definition, from: :rbs, result: result(type_name: "::Customer"))
    assert_equal [[uri(RBS_PATH), 0]], summarize(locations)
  end

  def test_implementation_jumps_to_ruby
    locations = resolver.goto(kind: :implementation, from: :ruby, result: result(constant: "::Customer", method_names: ["::Customer#name"]))
    assert_equal [[uri(RUBY_PATH), 0], [uri(RUBY_PATH), 4]], summarize(locations)

    locations = resolver.goto(kind: :implementation, from: :rbs, result: result(method_names: ["::Customer#name"]))
    assert_equal [[uri(RUBY_PATH), 4]], summarize(locations)

    # The implementation of a type name is the Ruby class
    locations = resolver.goto(kind: :implementation, from: :rbs, result: result(type_name: "::Customer"))
    assert_equal [[uri(RUBY_PATH), 0]], summarize(locations)
  end

  def test_new_falls_back_to_initialize
    locations = resolver.goto(kind: :definition, from: :ruby, result: result(method_names: ["::Customer.new"]))
    assert_equal [[uri(RBS_PATH), 1]], summarize(locations)

    locations = resolver.goto(kind: :implementation, from: :ruby, result: result(method_names: ["::Customer.new"]))
    assert_equal [[uri(RUBY_PATH), 1]], summarize(locations)
  end

  def test_type_definition_jumps_to_rbs_declarations
    locations = resolver.goto(
      kind: :type_definition,
      from: :ruby,
      result: result(method_names: ["::Customer#name"], type: "::Array[::_Greeter | ::greeting] | ::Customer")
    )

    assert_equal [[uri(RBS_PATH), 5], [uri(RBS_PATH), 8], [uri(RBS_PATH), 0]], summarize(locations)
  end

  def test_each_type_name
    names = [] #: Array[String]
    resolver.each_type_name("::Array[::String | nil] | { a: ::Integer } | singleton(::Foo) | 1 | bool | X") do |name|
      names << name.to_s
    end

    # Literals, `nil`, and `bool` are their classes, and the type variable `X` is skipped
    assert_equal ["::Array", "::String", "::NilClass", "::Integer", "::Foo", "::TrueClass", "::FalseClass"], names

    # A type that is not RBS syntax yields nothing
    names = [] #: Array[String]
    resolver.each_type_name("<% Logic %>") { names << _1.to_s }
    assert_equal [], names
  end

  def test_unknown_symbol
    assert_equal [], resolver.goto(kind: :definition, from: :ruby, result: result(constant: "::Nothing"))
    assert_equal [], resolver.goto(kind: :definition, from: :ruby, result: result(type_name: "::Nothing"))
    assert_equal [], resolver.goto(kind: :type_definition, from: :ruby, result: result(type: "::Nothing"))
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
