require "test_helper"

class HoverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep
  HoverContent = Services::HoverContent
  ContentChange = Services::ContentChange

  def dirs
    @dirs ||= []
  end

  def typecheck_service(steepfile: <<RUBY)
target :lib do
  check "hello.rb"
  signature "hello.rbs"
end
RUBY
    project = Project.new(steepfile_path: current_dir + "Steepfile")
    Project::DSL.parse(project, steepfile)

    Services::TypeCheckService.new(project: project)
  end

  def test_hover_content
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
number = 123
string = "foo"
array = [number, string]

puts array.join(", ")
RUBY
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 3).tap do |content|
        assert_instance_of HoverContent::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 0).tap do |content|
        assert_instance_of HoverContent::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 11).tap do |content|
        assert_instance_of HoverContent::VariableContent, content
        assert_equal [3,9]...[3, 15], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 8).tap do |content|
        assert_instance_of HoverContent::TypeContent, content
        assert_equal [3,8]...[3, 24], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal "::Array[(::Integer | ::String)]", content.type.to_s
      end
    end
  end

  def test_method_hover
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
number = 123
string = "foo"
array = [number, string]

puts array.join(", ")
RUBY
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 5, column: 12).tap do |content|
        assert_instance_of HoverContent::MethodCallContent, content
        assert_equal [5,5]...[5, 21], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal HoverContent::InstanceMethodName.new(TypeName("::Array"), :join), content.method_name
        assert_equal "::String", content.type.to_s
        assert_instance_of RBS::Definition::Method, content.definition
      end
    end
  end

  def test_hover_block
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
[1,2,3].map {|x| x.to_s }

RUBY
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 9).tap do |content|
        assert_instance_of HoverContent::MethodCallContent, content
        assert_equal [1,0]...[1, 25], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal HoverContent::InstanceMethodName.new(TypeName("::Array"), :map), content.method_name
        assert_equal "::Array[::String]", content.type.to_s
        assert_instance_of RBS::Definition::Method, content.definition
      end
    end
  end

  def test_hover_def
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)],
class Hello
  def do_something(x)
    String
  end
end
RUBY
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class Hello
  # Do something super for given argument `x`.
  def do_something: (Integer x) -> String
                  | (String x) -> String
end
RBS
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_instance_of HoverContent::DefinitionContent, content
        assert_equal [2,2]...[4, 5], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :do_something, content.method_name
        assert_equal "((::Integer | ::String)) -> ::String", content.method_type.to_s
        assert_equal ["(::Integer x) -> ::String", "(::String x) -> ::String"], content.definition.method_types.map(&:to_s)
        assert_instance_of RBS::Definition::Method, content.definition
        assert_equal "Do something super for given argument `x`.", content.comment_string
      end
    end
  end

  def test_hover_def_no_signature
    in_tmpdir do
      service = typecheck_service()
      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
class Hello
  def do_something(x)
    String
  end
end
RUBY
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_nil content
      end
    end
  end

  def test_hover_def_var
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)],
class Hello
  def foo(x, y = :y)
    y.to_s + "hello world"
  end
end
RUBY
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class Hello
  # foo method processes given argument.
  def foo: (Integer x) -> String
         | (String x, Symbol y) -> String
end
RBS
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 4).tap do |content|
        assert_instance_of HoverContent::VariableContent, content
        assert_equal [3,4]...[3, 5], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :y, content.name
        assert_equal "(::Symbol | nil)", content.type.to_s
      end
    end
  end

  def test_hover_on_rbs
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
type foo = Integer | String

class FooBar
  def f: (foo) -> void
end
RBS
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rbs"), line: 4, column: 11).tap do |content|
        assert_instance_of HoverContent::TypeAliasContent, content
        assert_instance_of RBS::Location::WithChildren, content.location

        assert_equal content.location.start_line, 4
        assert_equal content.location.start_column, 10
      end
    end
  end

  def test_hover_on_syntax_error
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
foo = 100
foo + "ba
RUBY
        }
      ) {}

      hover = HoverContent.new(service: service)

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 4).tap do |content|
        assert_nil content
      end
    end
  end
end
