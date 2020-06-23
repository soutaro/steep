require_relative "test_helper"

class ProjectTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep
  HoverContent = Steep::Project::HoverContent

  def dirs
    @dirs ||= []
  end

  def test_loader
    in_tmpdir do
      (current_dir+"lib").mkdir
      (current_dir + "lib/foo.rb").write <<CONTENT
class Foo
end
CONTENT

      (current_dir+"sig").mkdir
      (current_dir + "sig/foo.rbs").write <<CONTENT
class Foo
end
CONTENT

      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      loader = Project::FileLoader.new(project: project)
      loader.load_sources []
      loader.load_signatures

      target = project.targets[0]

      assert_equal Set[Pathname("lib/foo.rb")], Set.new(target.source_files.keys)
      assert_equal Set[Pathname("sig/foo.rbs")], Set.new(target.signature_files.keys)
    end
  end

  def test_hover_content
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
number = 123
string = "foo"
array = [number, string]

puts array.join(", ")
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 3).tap do |content|
        assert_instance_of Project::HoverContent::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 0).tap do |content|
        assert_instance_of Project::HoverContent::VariableContent, content
        assert_equal [1,0]...[1, 6], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :number, content.name
        assert_equal "::Integer", content.type.to_s
      end

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 11).tap do |content|
        assert_instance_of Project::HoverContent::VariableContent, content
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
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
number = 123
string = "foo"
array = [number, string]

puts array.join(", ")
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 5, column: 12).tap do |content|
        assert_instance_of HoverContent::MethodCallContent, content
        assert_equal [5,5]...[5, 21], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal HoverContent::InstanceMethodName.new(Names::Module.parse("::Array"), :join), content.method_name
        assert_equal "::String", content.type.to_s
        assert_instance_of RBS::Definition::Method, content.definition
      end
    end
  end

  def test_hover_block
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
[1,2,3].map {|x| x.to_s }
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 1, column: 9).tap do |content|
        assert_instance_of HoverContent::MethodCallContent, content
        assert_equal [1,0]...[1, 25], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal HoverContent::InstanceMethodName.new(Names::Module.parse("::Array"), :map), content.method_name
        assert_equal "::Array[::String]", content.type.to_s
        assert_instance_of RBS::Definition::Method, content.definition
      end
    end
  end

  def test_hover_def
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
  signature "hello.rbs"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
class Hello
  def do_something(x)
    String
  end
end
      EOF

      target.add_signature(Pathname("hello.rbs"), <<-EOF)
class Hello
  # Do something super for given argument `x`.
  def do_something: (Integer x) -> String
                  | (String x) -> String
end
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_instance_of HoverContent::DefinitionContent, content
        assert_equal [2,2]...[4, 5], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :do_something, content.method_name
        assert_equal "((::Integer | ::String)) -> ::String", content.method_type.to_s
        assert_equal ["(::Integer x) -> ::String", "(::String x) -> ::String"], content.definition.method_types.map(&:to_s)
        assert_instance_of RBS::Definition::Method, content.definition
        assert_equal "Do something super for given argument `x`.\n", content.comment_string
      end
    end
  end

  def test_hover_def_no_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
  signature "hello.rbs"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
class Hello
  def do_something(x)
    String
  end
end
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 2, column: 10).tap do |content|
        assert_nil content
      end
    end
  end

  def test_hover_def_var
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "hello.rb"
  signature "hello.rbs"
end
EOF

      target = project.targets[0]
      target.add_source(Pathname("hello.rb"), <<-EOF)
class Hello
  def foo(x, y = :y)
    y.to_s + "hello world"
  end
end
      EOF

      target.add_signature(Pathname("hello.rbs"), <<-EOF)
class Hello
  # foo method processes given argument.
  def foo: (Integer x) -> String
         | (String x, Symbol y) -> String
end
      EOF

      target.type_check(validate_signatures: false)

      hover = Project::HoverContent.new(project: project)

      hover.content_for(path: Pathname("hello.rb"), line: 3, column: 4).tap do |content|
        assert_instance_of Project::HoverContent::VariableContent, content
        assert_equal [3,4]...[3, 5], [content.location.line,content.location.column]...[content.location.last_line, content.location.last_column]
        assert_equal :y, content.name
        assert_equal "::Symbol", content.type.to_s
      end
    end
  end
end
