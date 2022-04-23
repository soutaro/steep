require "test_helper"

class RubyHoverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep
  HoverProvider = Services::HoverProvider
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

  def test_variable
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

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 3).tap do |content|
        assert_instance_of HoverProvider::Ruby::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 0).tap do |content|
        assert_instance_of HoverProvider::Ruby::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 3, column: 11).tap do |content|
        assert_instance_of HoverProvider::Ruby::VariableContent, content
        assert_equal [3,9]...[3, 15], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 3, column: 8).tap do |content|
        assert_instance_of HoverProvider::Ruby::TypeContent, content
        assert_equal [3,8]...[3, 24], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal "::Array[(::Integer | ::String)]", content.type.to_s
      end
    end
  end

  def test_method_call
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
number = 123
string = "foo"
array = [number, string]

puts array.join(", ")
[].compact(123)
array.foo_bar_baz
RUBY
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 5, column: 12).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [5, 11]...[5, 15], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Typed, content.method_call
        assert_equal [MethodName("::Array#join")], content.method_call.method_decls.map(&:method_name)
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 6, column: 6).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [6, 3]...[6, 10], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Error, content.method_call
        assert_equal "::Array[untyped]", content.method_call.return_type.to_s
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 7, column: 8).tap do |content|
        assert_instance_of HoverProvider::Ruby::TypeContent, content
        assert_equal [7, 0]...[7, 17], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal "untyped", content.type.to_s
      end
    end
  end

  def test_method_call_csend
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
number = 123
string = "foo"
array = [number, string]

array&.join(", ")
RUBY
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 5, column: 9).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [5, 7]...[5, 11], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Typed, content.method_call
        assert_equal [MethodName("::Array#join")], content.method_call.method_decls.map(&:method_name)
        assert_equal "(::String | nil)", content.method_call.return_type.to_s
      end
    end
  end

  def test_method_call_with_block
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
[1,2,3].map {|x| x.to_s }
RUBY
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 9).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [1,8]...[1,11], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Typed, content.method_call
        assert_equal "::Array[::String]", content.method_call.return_type.to_s
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 21).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [1,19]...[1,23], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Typed, content.method_call
        assert_equal "::String", content.method_call.return_type.to_s
      end
    end
  end

  def test_method_call_with_numblock
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)]
[1,2,3].map { _1.to_s }
RUBY
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 9).tap do |content|
        assert_instance_of HoverProvider::Ruby::MethodCallContent, content
        assert_equal [1,8]...[1,11], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_instance_of TypeInference::MethodCall::Typed, content.method_call
      end
    end
  end

  def test_method_definition
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<RUBY)],
class Hello
  def do_something(x)
    String
  end

  def self.foo
  end

  def bar
  end
end
RUBY
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
class Hello
  # Do something super for given argument `x`.
  def do_something: (Integer x) -> String
                  | (String x) -> String

  def self.foo: () -> void

  include _Foo
end

interface _Foo
  def bar: () -> String
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_instance_of HoverProvider::Ruby::DefinitionContent, content
        assert_equal [2,6]...[2,18], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal MethodName("::Hello#do_something"), content.method_name
        assert_equal "((::Integer | ::String)) -> ::String", content.method_type.to_s
        assert_equal ["(::Integer x) -> ::String", "(::String x) -> ::String"], content.definition.method_types.map(&:to_s)
        assert_instance_of RBS::Definition::Method, content.definition
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 6, column: 13).tap do |content|
        assert_instance_of HoverProvider::Ruby::DefinitionContent, content
        assert_equal [6,11]...[6,14], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal MethodName("::Hello.foo"), content.method_name
        assert_equal "() -> void", content.method_type.to_s
        assert_equal ["() -> void"], content.definition.method_types.map(&:to_s)
        assert_instance_of RBS::Definition::Method, content.definition
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 9, column: 10).tap do |content|
        assert_instance_of HoverProvider::Ruby::DefinitionContent, content
        assert_equal [9,6]...[9,9], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal MethodName("::_Foo#bar"), content.method_name
        assert_equal "() -> ::String", content.method_type.to_s
        assert_equal ["() -> ::String"], content.definition.method_types.map(&:to_s)
        assert_instance_of RBS::Definition::Method, content.definition
      end
    end
  end

  def test_method_definition_no_signature
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

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_instance_of HoverProvider::Ruby::TypeContent, content
      end
    end
  end

  def test_var_parameter
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

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 3, column: 4).tap do |content|
        assert_instance_of HoverProvider::Ruby::VariableContent, content
        assert_equal [3,4]...[3, 5], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :y, content.name
        assert_equal "(::Symbol | nil)", content.type.to_s
      end
    end
  end

  def test_constant
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<'RUBY')],
class Hello
  World = "Hello World!"
end
RUBY
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
# Hello world!
class Hello
end

# Another comment
class Hello
end

Hello::World: String
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 1, column: 7).tap do |content|
        assert_instance_of HoverProvider::Ruby::ConstantContent, content
        assert_equal [1,6]...[1,11], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal TypeName("::Hello"), content.full_name
        assert_equal "singleton(::Hello)", content.type.to_s
        assert_equal service.signature_services[:lib].latest_env.class_decls[TypeName("::Hello")], content.decl
      end

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 2, column: 5).tap do |content|
        assert_instance_of HoverProvider::Ruby::ConstantContent, content
        assert_equal [2,2]...[2,7], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal TypeName("::Hello::World"), content.full_name
        assert_equal "::String", content.type.to_s
        assert_equal service.signature_services[:lib].latest_env.constant_decls[TypeName("::Hello::World")], content.decl
      end
    end
  end

  def test_heredoc
    in_tmpdir do
      service = typecheck_service()

      service.update(
        changes: {
          Pathname("hello.rb") => [ContentChange.string(<<'RUBY')],
s = [<<HELLO, <<WORLD]
#{Hello}
HELLO
World
WORLD
RUBY
          Pathname("hello.rbs") => [ContentChange.string(<<RBS)]
# Hello world!
class Hello
end
RBS
        }
      ) {}

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 2, column: 4).tap do |content|
        assert_instance_of HoverProvider::Ruby::ConstantContent, content
      end
      hover.content_for(target: target, path: Pathname("hello.rb"), line: 4, column: 4).tap do |content|
        assert_instance_of HoverProvider::Ruby::TypeContent, content
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

      target = service.project.targets.find {|target| target.name == :lib }
      hover = HoverProvider::Ruby.new(service: service)

      hover.content_for(target: target, path: Pathname("hello.rb"), line: 3, column: 4).tap do |content|
        assert_nil content
      end
    end
  end
end
