require "test_helper"

class ScaffoldTest < Minitest::Test
  Scaffold = Steep::Drivers::Scaffold

  def with_sources(*sources, &block)
    Dir.mktmpdir do |dir|
      path = Pathname(dir)

      sources.each.with_index do |source, index|
        file = path + "source#{index}.rb"
        file.write(source)
      end

      yield path
    end
  end

  def stdout
    @stdout ||= StringIO.new
  end

  def stderr
    @stderr ||= StringIO.new
  end

  def test_class_module
    with_sources(<<-EOF) do |path|
class Hello1 < Array
end

module World
end

module Foo::Bar::Baz
end

module Foo
  class Hello; end
end
    EOF

      scaffold = Scaffold.new(source_paths: [path], stdout: stdout, stderr: stderr)

      assert_equal 0, scaffold.run

      assert_equal <<-RBS, stdout.string
class Hello1
end

module World
end

module Foo::Bar::Baz
end

class Foo::Hello
end

      RBS
    end
  end

  def test_defs
    with_sources(<<-EOF) do |path|
class Hello
  def foo(a, b=foo(), *c, d:, e: bar(), **f)
  end

  def self.bar(a = true, b = 3, c: [], d: nil)
  end
end
    EOF

      scaffold = Scaffold.new(source_paths: [path], stdout: stdout, stderr: stderr)

      assert_equal 0, scaffold.run

      assert_equal <<-RBS, stdout.string
class Hello
  def foo: (any, ?any, *any, d: any, ?e: any, **any) -> any
  def self.bar: (?bool, ?Integer, ?c: Array[any], ?d: any) -> any
end

      RBS
    end
  end

  def test_ivars
    with_sources(<<-EOF) do |path|
class Hello
  def initialize
    @name = @email
  end
end
    EOF

      scaffold = Scaffold.new(source_paths: [path], stdout: stdout, stderr: stderr)

      assert_equal 0, scaffold.run

      assert_equal <<-RBS, stdout.string
class Hello
  @name: any
  @email: any
  def initialize: () -> any
end

      RBS
    end
  end
end
