require_relative "test_helper"

class SymbolProviderTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  SymbolProvider = Services::SymbolProvider

  def dir
    @dir ||= Pathname(Dir.mktmpdir)
  end

  def project
    @project ||= Project.new(steepfile_path: dir + "Steepfile").tap do |project|
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
          check "inline", inline: true
        end
      end
    end
  end

  # @rbs () { (Steep::Server::ChangeBuffer::changes) -> void } -> Steep::Services::TypeCheckService
  def type_check_service()
    changes = {} #: Steep::Server::ChangeBuffer::changes
    yield changes

    type_check = Services::TypeCheckService.new(project: project)
    type_check.update(changes: changes)
    type_check
  end

  # Returns what is at the position as strings, with the keys that are present
  def symbols_at(type_check, path, line, column) #: Hash[Symbol, untyped]
    result = SymbolProvider.new(service: type_check).symbols_at(path: dir + path, line: line, column: column)

    hash = {} #: Hash[Symbol, untyped]
    hash[:constant] = result.constant.to_s if result.constant
    hash[:type_name] = result.type_name.to_s if result.type_name
    hash[:method_names] = result.method_names.map(&:to_s) unless result.method_names.empty?
    hash[:type] = result.type.to_s if result.type
    hash
  end

  def test_constant_in_ruby
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  VERSION: String
  SIZE: Integer
end
RBS
      changes[Pathname("lib/customer.rb")] = [ContentChange.string(<<RUBY)]
class Customer
  VERSION = "0.1.0"
end

Customer::SIZE + 2
RUBY
    end

    # The class name is a constant, and its type is the singleton
    assert_equal({ constant: "::Customer", type: "singleton(::Customer)" }, symbols_at(type_check, "lib/customer.rb", 1, 10))

    # The constant assignment
    assert_equal({ constant: "::Customer::VERSION", type: "::String" }, symbols_at(type_check, "lib/customer.rb", 2, 4))

    # The constant reference
    assert_equal({ constant: "::Customer::SIZE", type: "::Integer" }, symbols_at(type_check, "lib/customer.rb", 5, 12))
  end

  def test_constant_in_rbs
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  VERSION: String
end

module Steep::Server
end
RBS
    end

    assert_equal({ constant: "::Customer" }, symbols_at(type_check, "sig/customer.rbs", 1, 8))
    assert_equal({ constant: "::Customer::VERSION" }, symbols_at(type_check, "sig/customer.rbs", 2, 4))
    assert_equal({ constant: "::Steep::Server" }, symbols_at(type_check, "sig/customer.rbs", 5, 12))

    # The type of the constant is a type name
    assert_equal({ type_name: "::String" }, symbols_at(type_check, "sig/customer.rbs", 2, 12))

    # Not on a name
    assert_equal({}, symbols_at(type_check, "sig/customer.rbs", 2, 9))
  end

  def test_method_definition
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: () -> void

  def self.bar: () -> void

  def self?.baz: () -> void
end
RBS
      changes[Pathname("lib/customer.rb")] = [ContentChange.string(<<RUBY)]
class Customer
  def foo
  end

  def self.bar
  end
end
RUBY
    end

    assert_equal({ method_names: ["::Customer#foo"] }, symbols_at(type_check, "sig/customer.rbs", 2, 7))
    assert_equal({ method_names: ["::Customer.bar"] }, symbols_at(type_check, "sig/customer.rbs", 4, 13))

    # `self?.` defines both
    result = symbols_at(type_check, "sig/customer.rbs", 6, 13)
    assert_equal [:method_names], result.keys
    assert_equal ["::Customer#baz", "::Customer.baz"], result[:method_names].sort

    # The `def` in Ruby, whose expression type is the symbol of the method name
    assert_equal({ method_names: ["::Customer#foo"], type: "::Symbol" }, symbols_at(type_check, "lib/customer.rb", 2, 8))
    assert_equal({ method_names: ["::Customer.bar"], type: "::Symbol" }, symbols_at(type_check, "lib/customer.rb", 5, 13))
  end

  def test_method_call
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: () -> String

  def self.bar: () -> void

  def each: () { (Integer) -> void } -> void
end
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
Customer.new.foo()
Customer.bar()

Customer.no_method_error()
(_ = Customer).bar()

Customer.new.each do |x| end
RUBY
    end

    # The method call, and the type of the call expression
    assert_equal({ method_names: ["::Customer#foo"], type: "::String" }, symbols_at(type_check, "lib/main.rb", 1, 16))
    assert_equal({ method_names: ["::Customer.bar"], type: "void" }, symbols_at(type_check, "lib/main.rb", 2, 11))

    # Errors and untyped receivers give no method
    refute_includes symbols_at(type_check, "lib/main.rb", 4, 11).keys, :method_names
    refute_includes symbols_at(type_check, "lib/main.rb", 5, 18).keys, :method_names

    # The call with a block
    assert_equal ["::Customer#each"], symbols_at(type_check, "lib/main.rb", 7, 15)[:method_names]

    # The receiver is a constant, and its type is the singleton
    assert_equal({ constant: "::Customer", type: "singleton(::Customer)" }, symbols_at(type_check, "lib/main.rb", 1, 3))
  end

  def test_type_name_in_rbs
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: ([String, string] key) -> String
end
RBS
    end

    assert_equal({ type_name: "::String" }, symbols_at(type_check, "sig/customer.rbs", 2, 16))
    assert_equal({ type_name: "::string" }, symbols_at(type_check, "sig/customer.rbs", 2, 24))
  end

  def test_type_name_in_annotations
    type_check = type_check_service do |changes|
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
path = nil #: String?
[].map { } #$ String?
RUBY
    end

    # The type assertion, and the type of the asserted expression
    assert_equal({ type_name: "::String", type: "::String | nil" }, symbols_at(type_check, "lib/main.rb", 1, 16))

    # The type application
    assert_equal "::String", symbols_at(type_check, "lib/main.rb", 2, 16)[:type_name]
  end

  def test_inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/inline.rb")] = [ContentChange.string(<<RUBY)]
class Foo
  # @rbs () -> (String | Integer | nil)
  def bar
    nil #: String?
  end
end
RUBY
    end

    # The type name in the inline annotation
    assert_equal({ type_name: "::String" }, symbols_at(type_check, "inline/inline.rb", 2, 16))

    # The type assertion in the Ruby code
    assert_equal({ type_name: "::String", type: "::String | nil" }, symbols_at(type_check, "inline/inline.rb", 4, 14))

    # The method definition
    assert_equal({ method_names: ["::Foo#bar"], type: "::Symbol" }, symbols_at(type_check, "inline/inline.rb", 3, 7))
  end

  def test_type_of_expression
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def name: () -> String?
end
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
customer = Customer.new()
name = customer.name
[customer, name]
RUBY
    end

    # A variable is not a symbol, and its type is the class
    assert_equal({ type: "::Customer" }, symbols_at(type_check, "lib/main.rb", 2, 10))

    # The types are in RBS syntax
    assert_equal({ type: "::String | nil" }, symbols_at(type_check, "lib/main.rb", 2, 2))
    assert_equal({ type: "::Array[::Customer | ::String | nil]" }, symbols_at(type_check, "lib/main.rb", 3, 0))
  end

  def test_unknown_file
    type_check = type_check_service do |changes|
    end

    assert_equal({}, symbols_at(type_check, "lib/nothing.rb", 1, 0))
  end
end
