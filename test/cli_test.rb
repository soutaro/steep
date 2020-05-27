require "test_helper"

class CLITest < Minitest::Test
  include ShellHelper
  include TestHelper

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
      stdout, _ = sh!(*steep, "version")

      assert_equal "#{Steep::VERSION}", stdout.chomp
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

      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      stdout, _ = sh!(*steep, "annotations", "foo.rb")

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
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
end
      EOF
      stdout, _ = sh!(*steep, "validate")

      assert_equal "", stdout
    end
  end

  def test_watch
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "app"
  signature "sig"
end
      EOF

      (current_dir + "app").mkdir
      (current_dir + "app/lib").mkdir
      (current_dir + "app/models").mkdir
      (current_dir + "sig").mkdir

      (current_dir + "app/models/person.rb").write <<RUBY
# steep watch won't type check this file.
class Person
end

"hello" + 3
RUBY

      r, w = IO.pipe
      pid = spawn(*steep.push("watch", "app/lib"), out: w, chdir: current_dir.to_s)
      w.close

      begin
        stdout = ""
        Thread.new do
          while line = r.gets
            stdout << line
          end
        end

        finally_holds do
          assert_equal <<EOF, stdout
👀 Watching directories, Ctrl-C to stop.
EOF
        end

        (current_dir + "app/lib/foo.rb").write <<RUBY
1 + ""
RUBY

        finally_holds do
          assert_equal <<EOF, stdout
👀 Watching directories, Ctrl-C to stop.
🔬 Type checking updated files...
app/lib/foo.rb:1:0: UnresolvedOverloading: receiver=::Integer, method_name=+, method_types=(::Integer) -> ::Integer | (::Float) -> ::Float | (::Rational) -> ::Rational | (::Complex) -> ::Complex (1 + "")
EOF
        end
      ensure
        Process.kill(:INT, pid)
        Process.waitpid pid
      end
    end
  end
end
