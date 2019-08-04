require "test_helper"

class CLITest < Minitest::Test
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def envs
    @envs ||= []
  end

  def steep
    ["bundle", "exec", "--gemfile=#{__dir__}/../Gemfile", "#{__dir__}/../exe/steep"]
  end

  def test_version
    in_tmpdir do
      stdout, _ = sh! *steep, "version"

      assert_equal "#{Steep::VERSION}", stdout.chomp
    end
  end

  def test_scaffold
    in_tmpdir do
      (current_dir + "foo.rb").write(<<-RUBY)
class Foo
  def hello(x, y)
    x + y
  end
end
      RUBY

      stdout, _ = sh! *steep, "scaffold", "foo.rb"

      assert_equal <<-RBS, stdout
class Foo
  def hello: (any, any) -> any
end

      RBS
    end
  end

  def test_annotations
    in_tmpdir do
      (current_dir + "foo.rb").write(<<-RUBY)
class Foo
  # @dynamic name, email

  def hello(x, y)
    # @type var x: Foo[Integer]
    x + y
  end
end
      RUBY

      stdout, _ = sh! *steep, "annotations", "foo.rb"

      assert_equal <<-RBS, stdout
foo.rb:1:0:class:\tclass Foo
   @dynamic name, email
foo.rb:4:2:def:\tdef hello(x, y)
   @type var x: Foo[Integer]
      RBS
    end
  end

  def test_validate
    in_tmpdir do
      stdout, _ = sh! *steep, "validate"

      assert_equal "", stdout
    end
  end
end
