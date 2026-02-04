require_relative "test_helper"

class GotoServiceTest < Minitest::Test
  include Steep
  include TestHelper

  ContentChange = Services::ContentChange
  TypeCheckService = Services::TypeCheckService
  GotoService = Services::GotoService

  def dir
    @dir ||= Pathname(Dir.mktmpdir)
  end

  def assignment
    Services::PathAssignment.all
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
    changes.each_key do |path|
      if target = project.target_for_source_path(path)
        type_check.typecheck_source(path: path, target: target)
      end
    end
    type_check
  end

  def test_goto_definition_sig_class
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  VERSION: String
end

class ::Customer
  SIZE: Integer
end
RBS
      changes[Pathname("lib/customer.rb")] = [ContentChange.string(<<RUBY)]
class Customer
  VERSION = "0.1.0"
end

class Customer
  SIZE = 30
end
RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "sig/customer.rbs", line: 2, column: 4).tap do |locations|
    end
  end

  def test_query_at_code_const
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  VERSION: String
end

class ::Customer
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

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "lib/customer.rb", line: 1, column: 10).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::ConstantQuery, query
        assert_equal RBS::TypeName.parse("::Customer"), query.name
        assert_predicate query, :from_ruby?
      end
    end

    service.query_at(path: dir + "lib/customer.rb", line: 2, column: 4).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::ConstantQuery, query
        assert_equal RBS::TypeName.parse("::Customer::VERSION"), query.name
        assert_predicate query, :from_ruby?
      end
    end

    service.query_at(path: dir + "lib/customer.rb", line: 5, column: 12).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::ConstantQuery, query
        assert_equal RBS::TypeName.parse("::Customer::SIZE"), query.name
        assert_predicate query, :from_ruby?
      end
    end
  end

  def test_query_at_rbs_const
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  VERSION: String
end

class ::Customer
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

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "sig/customer.rbs", line: 1, column: 10).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::ConstantQuery, query
        assert_equal RBS::TypeName.parse("::Customer"), query.name
        assert_predicate query, :from_rbs?
      end
    end

    service.query_at(path: dir + "sig/customer.rbs", line: 2, column: 6).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::ConstantQuery, query
        assert_equal RBS::TypeName.parse("::Customer::VERSION"), query.name
        assert_predicate query, :from_rbs?
      end
    end
  end

  def test_query_at_method_def
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

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "sig/customer.rbs", line: 2, column: 7).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal InstanceMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :foo), query.name
        assert_predicate query, :from_rbs?
      end
    end

    service.query_at(path: dir + "sig/customer.rbs", line: 4, column: 13).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal SingletonMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :bar), query.name
        assert_predicate query, :from_rbs?
      end
    end

    service.query_at(path: dir + "sig/customer.rbs", line: 6, column: 13).tap do |qs|
      assert_equal 2, qs.size

      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal SingletonMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :baz), query.name
        assert_predicate query, :from_rbs?
      end

      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal InstanceMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :baz), query.name
        assert_predicate query, :from_rbs?
      end
    end

    service.query_at(path: dir + "lib/customer.rb", line: 2, column: 8).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal InstanceMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :foo), query.name
        assert_predicate query, :from_ruby?
      end
    end

    service.query_at(path: dir + "lib/customer.rb", line: 5, column: 13).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal SingletonMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :bar), query.name
        assert_predicate query, :from_ruby?
      end
    end
  end

  def test_query_at_type
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: ([String, string] key) -> String
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "sig/customer.rbs", line: 2, column: 16).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::String"), query.name
      end
    end

    service.query_at(path: dir + "sig/customer.rbs", line: 2, column: 24).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::string"), query.name
      end
    end
  end

  def test_query_at_method_call
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: () -> void

  def self.bar: () -> void

  def self?.baz: () -> void
end
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
Customer.new.foo()
Customer.bar()

Customer.no_method_error()
(_ = Customer).bar()
RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "lib/main.rb", line: 1, column: 16).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal InstanceMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :foo), query.name
      end
    end

    service.query_at(path: dir + "lib/main.rb", line: 2, column: 11).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        assert_instance_of Services::GotoService::MethodQuery, query
        assert_equal SingletonMethodName.new(type_name: RBS::TypeName.parse("::Customer"), method_name: :bar), query.name
      end
    end

    service.query_at(path: dir + "lib/main.rb", line: 4, column: 11).tap do |qs|
      assert_empty qs
    end

    service.query_at(path: dir + "lib/main.rb", line: 5, column: 18).tap do |qs|
      assert_empty qs
    end
  end

  def test_query_at__assertion
    type_check = type_check_service do |changes|
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
path = nil #: String?
RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "lib/main.rb", line: 1, column: 16).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        # @type var query: Steep::Services::GotoService::TypeNameQuery
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::String"), query.name
      end
    end
  end

  def test_query_at__application
    type_check = type_check_service do |changes|
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
[].map { } #$ String?
RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "lib/main.rb", line: 1, column: 16).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        # @type var query: Steep::Services::GotoService::TypeNameQuery
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::String"), query.name
      end
    end
  end

  def test_query_at__inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/inline.rb")] = [ContentChange.string(<<-RUBY)]
class Foo
  # @rbs () -> (String | Integer | nil)
  def bar
    nil #: String?
  end
end

      RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.query_at(path: dir + "inline/inline.rb", line: 2, column: 16).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        # @type var query: Steep::Services::GotoService::TypeNameQuery
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::String"), query.name
      end
    end

    service.query_at(path: dir + "inline/inline.rb", line: 4, column: 14).tap do |qs|
      assert_equal 1, qs.size
      assert_any!(qs) do |query|
        # @type var query: Steep::Services::GotoService::TypeNameQuery
        assert_instance_of Services::GotoService::TypeNameQuery, query
        assert_equal RBS::TypeName.parse("::String"), query.name
      end
    end
  end

  def test_constant_locations
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  module ::Customer2
  end
end

Customer::NAME: String
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
class Customer
  module ::Customer2
  end

  NAME = "FOO"
end
RUBY
    end

    type_check.source_files.each_key do |path|
      type_check.typecheck_source(path: path, target: type_check.project.target_for_source_path(path))
    end
    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.constant_definition_in_ruby(RBS::TypeName.parse("::Customer"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of Parser::Source::Range, loc
        assert_equal "Customer", loc.source
        assert_equal 1, loc.line
      end
    end

    service.constant_definition_in_rbs(RBS::TypeName.parse("::Customer"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "Customer", loc.source
        assert_equal 1, loc.start_line
      end
    end

    service.constant_definition_in_ruby(RBS::TypeName.parse("::Customer2"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of Parser::Source::Range, loc
        assert_equal "::Customer2", loc.source
        assert_equal 2, loc.line
      end
    end

    service.constant_definition_in_rbs(RBS::TypeName.parse("::Customer2"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "::Customer2", loc.source
        assert_equal 2, loc.start_line
      end
    end

    service.constant_definition_in_ruby(RBS::TypeName.parse("::Customer::NAME"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of Parser::Source::Range, loc
        assert_equal "NAME", loc.source
        assert_equal 5, loc.line
      end
    end

    service.constant_definition_in_rbs(RBS::TypeName.parse("::Customer::NAME"), locations: []).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "Customer::NAME", loc.source
        assert_equal 6, loc.start_line
      end
    end
  end

  def test_method_locations
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: () -> void

  alias bar foo

  attr_accessor baz: String

  extend _Finder
end

interface _Finder
  def find: () -> void
end
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
class Customer
  def foo
  end

  def self.find
  end
end
RUBY
    end

    type_check.source_files.each_key do |path|
      type_check.typecheck_source(path: path, target: type_check.project.target_for_source_path(path))
    end
    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.method_locations(MethodName("::Customer#foo"), locations: [], in_ruby: true, in_rbs: true).tap do |locs|
      assert_equal 2, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "foo", loc.source
        assert_equal 2, loc.start_line
      end

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name
        assert_instance_of Parser::Source::Range, loc
        assert_equal "foo", loc.source
        assert_equal 2, loc.line
      end
    end

    service.method_locations(MethodName("::Customer#bar"), locations: [], in_ruby: true, in_rbs: true).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "bar", loc.source
        assert_equal 4, loc.start_line
      end
    end

    service.method_locations(MethodName("::Customer#baz="), locations: [], in_ruby: true, in_rbs: true).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "baz", loc.source
        assert_equal 6, loc.start_line
      end
    end

    service.method_locations(MethodName("::Customer.find"), locations: [], in_ruby: true, in_rbs: true).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of Parser::Source::Range, loc
        assert_equal "find", loc.source
        assert_equal 5, loc.line
      end
    end

    service.method_locations(MethodName("::_Finder#find"), locations: [], in_ruby: true, in_rbs: true).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "find", loc.source
        assert_equal 12, loc.start_line
      end
    end
  end

  def test_method_locations_error
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  def foo: (Integer, String) -> void
         | (String) -> void
end
RBS
      changes[Pathname("lib/main.rb")] = [ContentChange.string(<<RUBY)]
Customer.new.foo()
RUBY
    end

    type_check.source_files.each_key do |path|
      type_check.typecheck_source(path: path, target: type_check.project.target_for_source_path(path))
    end
    service = Services::GotoService.new(type_check: type_check, assignment: assignment)
    queries = service.query_at(path: Pathname("lib/main.rb"), line: 1, column: 16)

    assert_equal 2, queries.size
    queries.each do |query|
      assert_instance_of Services::GotoService::MethodQuery, query
      assert_equal MethodName("::Customer#foo"), query.name
    end
  end

  def test_type_name_locations
    type_check = type_check_service do |changes|
      changes[Pathname("sig/customer.rbs")] = [ContentChange.string(<<RBS)]
class Customer
  type loc = Location::WithChildren[:name | :args]
end

class Customer
  interface _Base
  end
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.type_name_locations(RBS::TypeName.parse("::Customer")).tap do |locs|
      assert_equal 2, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "Customer", loc.source
        assert_equal 1, loc.start_line
      end

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "Customer", loc.source
        assert_equal 5, loc.start_line
      end
    end

    service.type_name_locations(RBS::TypeName.parse("::Customer::loc")).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "loc", loc.source
        assert_equal 2, loc.start_line
      end
    end

    service.type_name_locations(RBS::TypeName.parse("::Customer::_Base")).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "_Base", loc.source
        assert_equal 6, loc.start_line
      end
    end
  end

  def test_type_name_locations__inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/hello.rb")] = [ContentChange.string(<<RBS)]
class Hello
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.type_name_locations(RBS::TypeName.parse("::Hello")).tap do |locs|
      assert_equal 1, locs.size

      assert_any!(locs) do |target, loc|
        assert_equal :lib, target.name

        assert_instance_of RBS::Location, loc
        assert_equal "Hello", loc.source
        assert_equal 1, loc.start_line
      end
    end
  end

  def test_new_method_definition
    type_check = type_check_service do |changes|
      changes[Pathname("sig/a.rbs")] = [ContentChange.string(<<RBS)]
class Foo
  def initialize: (String) -> void
end

class Bar
end

class Baz
  def self.new: (Integer) -> Baz
end
RBS

      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<RBS)]
Foo.new("foo")
Bar.new()
Baz.new(123)
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "lib/test.rb", line: 1, column: 6).tap do |locs|
      assert_any!(locs) do |loc|
        assert_instance_of RBS::Location, loc
        assert_equal "initialize", loc.source
        assert_equal 2, loc.start_line
        assert_equal Pathname("sig/a.rbs"), loc.buffer.name
      end
    end

    service.definition(path: dir + "lib/test.rb", line: 2, column: 6).tap do |locs|
      assert_any!(locs) do |loc|
        assert_instance_of RBS::Location, loc
        assert_equal "initialize", loc.source
        assert_equal Pathname("basic_object.rbs"), Pathname(loc.buffer.name).basename
      end
    end

    service.definition(path: dir + "lib/test.rb", line: 3, column: 6).tap do |locs|
      assert_any!(locs) do |loc|
        assert_instance_of RBS::Location, loc
        assert_equal "new", loc.source
        assert_equal 9, loc.start_line
        assert_equal Pathname("sig/a.rbs"), loc.buffer.name
      end
    end
  end

  def test_method_definition__inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/a.rb")] = [ContentChange.string(<<RBS)]
class Foo
  def hello
  end
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.method_locations(MethodName("::Foo#hello"), in_ruby: false, in_rbs: true, locations: []).tap do |result|
      assert_any!(result) do |_target, loc|
        assert_instance_of RBS::Location, loc
        assert_equal "hello", loc.source
        assert_equal 2, loc.start_line
        assert_equal Pathname("inline/a.rb"), loc.buffer.name
      end
    end
  end

  def test_new_method_definition__inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/a.rb")] = [ContentChange.string(<<RBS)]
class Foo
  def initialize
  end
end

Foo.new
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "inline/a.rb", line: 6, column: 6).tap do |locs|
      assert_any!(locs) do |loc|
        assert_instance_of RBS::Location, loc
        assert_equal "initialize", loc.source
        assert_equal 2, loc.start_line
        assert_equal Pathname("inline/a.rb"), loc.buffer.name
      end
    end
  end

  def test_class_constant__inline
    type_check = type_check_service do |changes|
      changes[Pathname("inline/a.rb")] = [ContentChange.string(<<RBS)]
class Foo
  def initialize
  end
end

Foo.new
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "inline/a.rb", line: 6, column: 1).tap do |locs|
      assert_any!(locs) do |loc|
        assert_instance_of RBS::Location, loc
        assert_equal "Foo", loc.source
        assert_equal 1, loc.start_line
        assert_equal Pathname("inline/a.rb"), loc.buffer.name
      end
    end
  end

  def test_new_method_impl
    type_check = type_check_service do |changes|
      changes[Pathname("sig/a.rbs")] = [ContentChange.string(<<RBS)]
class Foo
  def initialize: (String) -> void
end

class Baz
  def self.new: (Integer) -> Baz
end
RBS

      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<RBS)]
class Foo
  def initialize(string)
  end
end

class Baz
  def self.new(i)
    super()
  end
end

Foo.new("foo")
Baz.new(123)
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.implementation(path: dir + "lib/test.rb", line: 12, column: 6).tap do |locs|
      assert_any!(locs, size: 1) do |loc|
        assert_instance_of Parser::Source::Range, loc
        assert_equal "initialize", loc.source
        assert_equal 2, loc.line
      end
    end

    service.implementation(path: dir + "lib/test.rb", line: 13, column: 6).tap do |locs|
      assert_any!(locs, size: 1) do |loc|
        assert_instance_of Parser::Source::Range, loc
        assert_equal "new", loc.source
        assert_equal 7, loc.line
      end
    end
  end

  def test_method_block
    type_check = type_check_service do |changes|
      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<RBS)]
[].each do |x|
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "lib/test.rb", line: 1, column: 4).tap do |locs|
      assert_any!(locs, size: 1) do |loc|
        assert_equal Pathname("array.rbs"), Pathname(loc.buffer.name).basename
      end
    end
  end

  def test_method_block_inner
    type_check = type_check_service do |changes|
      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<RBS)]
[].each do |x|
  nil.to_s
end
RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.definition(path: dir + "lib/test.rb", line: 2, column: 8).tap do |locs|
      assert_any!(locs, size: 1) do |loc|
        assert_equal Pathname("nil_class.rbs"), Pathname(loc.buffer.name).basename
      end
    end
  end

  def test_goto_definition_wrt_assignment
    type_check = type_check_service do |changes|
      changes[Pathname("sig/a.rbs")] = [ContentChange.string(<<RBS)]
class Customer
end
RBS
      changes[Pathname("sig/b.rbs")] = [ContentChange.string(<<RBS)]
class Customer
end
RBS
      changes[Pathname("lib/customer.rb")] = [ContentChange.string(<<RUBY)]
class Customer
end
RUBY
    end

    a = Services::PathAssignment.new(index: 0, max_index: 1)
    a.assign!([:lib, Pathname("sig/a.rbs")], 0)
    a.assign!([:lib, Pathname("sig/b.rbs")], 1)
    Services::GotoService.new(type_check: type_check, assignment: a).tap do |service|
      service.definition(path: dir + "lib/customer.rb", line: 1, column: 10).tap do |locs|
        assert_equal [Pathname("sig/a.rbs")], locs.map(&:name)
      end
    end

    b = Services::PathAssignment.new(index: 0, max_index: 1)
    b.assign!([:lib, Pathname("sig/a.rbs")], 1)
    b.assign!([:lib, Pathname("sig/b.rbs")], 0)
    Services::GotoService.new(type_check: type_check, assignment: b).tap do |service|
      service.definition(path: dir + "lib/customer.rb", line: 1, column: 10).tap do |locs|
        assert_equal [Pathname("sig/b.rbs")], locs.map(&:name)
      end
    end
  end

  def test_go_to_type_definition
    type_check = type_check_service do |changes|
      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<~RUBY)]
        Foo.new
      RUBY
      changes[Pathname("sig/foo.rbs")] = [ContentChange.string(<<~RBS)]
        class Foo
        end
      RBS
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.type_definition(path: dir + "lib/test.rb", line: 1, column: 5).tap do |locs|
      assert_equal 1, locs.size
      assert_equal "Foo", locs[0].source
    end
  end

  def test_go_to_type_definition2
    type_check = type_check_service do |changes|
      changes[Pathname("lib/test.rb")] = [ContentChange.string(<<~RUBY)]
        x = true #: bool
        y = 1 #: 1
        z = [1]
      RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.type_definition(path: dir + "lib/test.rb", line: 1, column: 3).tap do |locs|
      assert_equal 2, locs.size
      assert locs.find {|loc| loc.source == "TrueClass" }
      assert locs.find {|loc| loc.source == "FalseClass" }
    end

    service.type_definition(path: dir + "lib/test.rb", line: 2, column: 3).tap do |locs|
      assert_equal 1, locs.size
      assert locs.find {|loc| loc.source == "Integer" }
    end

    service.type_definition(path: dir + "lib/test.rb", line: 3, column: 3).tap do |locs|
      assert_equal 2, locs.size
      assert locs.find {|loc| loc.source == "Integer" }
      assert locs.find {|loc| loc.source == "Array" }
    end
  end

  def test_go_to_definition_class_alias
    skip "Type name resolution for module/class aliases is changed in RBS 3.10/4.0"

    type_check = type_check_service do |changes|
      changes[Pathname("inline/test.rb")] = [ContentChange.string(<<~RUBY)]
MyString = String #: class-alias
MyString
x = nil #: MyString?
      RUBY
    end

    service = Services::GotoService.new(type_check: type_check, assignment: assignment)

    service.type_definition(path: dir + "inline/test.rb", line: 2, column: 3).tap do |locs|
      assert_equal 1, locs.size
      assert_equal "MyString", locs[0].source
    end

    service.type_definition(path: dir + "inline/test.rb", line: 3, column: 15).tap do |locs|
      assert_equal 2, locs.size
      assert locs.find {|loc| loc.source == "MyString" }
      assert locs.find {|loc| loc.source == "NilClass" }
    end
  end
end
