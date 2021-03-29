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
      stdout = sh!(*steep, "version")

      assert_equal "#{Steep::VERSION}", stdout.chomp
    end
  end

  def test_check_success
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh(*steep, "check")

      assert_predicate status, :success?, stdout
      assert_match /No type error detected\./, stdout
    end
  end

  def test_check_failure
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check")

      refute_predicate status, :success?, stdout
      assert_match /Detected 1 problem from 1 file/, stdout
    end
  end

  def test_check_expectations_success
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match /Expectations satisfied:/, stdout
    end
  end

  def test_check_expectations_lineno_changed
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)



1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?, stdout
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?, stdout

      assert_match /Expectations unsatisfied:/, stdout
      assert_match /0 expected diagnostics/, stdout
      assert_match /1 unexpected diagnostic/, stdout
      assert_match /1 missing diagnostic/, stdout
    end
  end

  def test_check_expectations_fail
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?, stdout
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?, stdout

      assert_match /Expectations unsatisfied:/, stdout
      assert_match /0 expected diagnostics/, stdout
      assert_match /0 unexpected diagnostics/, stdout
      assert_match /1 missing diagnostic/, stdout
    end
  end

  def test_check_expectations_fail2
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb", "bar.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      (current_dir + "bar.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--save-expectation")
      assert_predicate status, :success?, stdout
      assert_match /Saved expectations in steep_expectations\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation", "foo.rb")
      refute_predicate status, :success?, stdout

      assert_match /Expectations unsatisfied:/, stdout
      assert_match /0 expected diagnostics/, stdout
      assert_match /0 unexpected diagnostics/, stdout
      assert_match /1 missing diagnostic/, stdout

      stdout, status = sh(*steep, "check", "--with-expectation", "bar.rb")
      assert_predicate status, :success?, stdout

      assert_match /Expectations satisfied:/, stdout
      assert_match /1 expected diagnostic/, stdout
    end
  end

  def test_check_broken
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  signature "foo.rbs"
end
      EOF

      (current_dir + "foo.rbs").write(<<-EOF.encode(Encoding::EUC_JP).force_encoding(Encoding::UTF_8))
無効なUTF-8ファイル
      EOF

      stdout, status = sh(*steep, "check")
      refute_predicate status, :success?, stdout
      assert_match /invalid byte sequence in UTF-8/, stdout.force_encoding(Encoding::ASCII_8BIT)
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

      stdout = sh!(*steep, "annotations", "foo.rb")

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
      stdout = sh!(*steep, "validate")

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

      (current_dir + "app/lib/foo.rb").write <<RUBY
# steep will type check this file.
1.__first_error__
RUBY

      r, w = IO.pipe
      pid = spawn(*steep.push("watch", "app/lib"), out: w, chdir: current_dir.to_s)
      w.close

      output = ""

      begin
        read_thread = Thread.new do
          while line = r.gets()
            output << line
          end
        end

        finally_holds do
          assert_includes output, "app/lib/foo.rb:2:2: [error] Type `::Integer` does not have method `__first_error__`"
          refute_includes output, "app/models/person.rb"
        end

        (current_dir + "app/lib/foo.rb").write <<RUBY
# steep will type check this file.
1.__second_error__
RUBY

        finally_holds do
          assert_includes output, "Type checking updated files..."
          assert_includes output, "app/lib/foo.rb:2:2: [error] Type `::Integer` does not have method `__second_error__`"
          refute_includes output, "app/models/person.rb"
        end
      ensure
        Process.kill(:INT, pid)
        read_thread.join

        Process.waitpid(pid)
        assert_equal 0, $?.exitstatus
      end
    end
  end

  def test_watch_file
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
class Person
end

"hello" + 3
RUBY

      r, w = IO.pipe
      pid = spawn(*steep.push("watch", "app/models/person.rb"), out: w, chdir: current_dir.to_s)
      w.close

      output = ""

      begin
        read_thread = Thread.new do
          while line = r.gets
            output << line
          end
        end

        (current_dir + "app/models/group.rb").write <<RUBY
1+"2"
RUBY

        finally_holds do
          assert_includes output, "app/models/person.rb"
          refute_includes output, "app/models/group.rb"
        end
      ensure
        Process.kill(:INT, pid)
        read_thread.join
        Process.waitpid(pid)
        assert_equal 0, $?.exitstatus
      end

    end
  end

  def test_stats_default_no_tty
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, _, status = sh3(*steep, "stats")

      assert_predicate status, :success?, stdout
      assert_equal <<CSV, stdout
Target,File,Status,Typed calls,Untyped calls,All calls,Typed %
app,foo.rb,success,1,0,1,100
CSV
    end
  end

  def test_stats_csv
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, _, status = sh3(*steep, "stats", "--format=csv")

      assert_predicate status, :success?, stdout
      assert_equal <<CSV, stdout
Target,File,Status,Typed calls,Untyped calls,All calls,Typed %
app,foo.rb,success,1,0,1,100
CSV
    end
  end

  def test_stats_table
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, _, status = sh3(*steep, "stats", "--format=table")

      assert_predicate status, :success?, stdout
      assert_equal <<CSV, stdout
 Target  File      Status   Typed calls  Untyped calls  All calls  Typed %
---------------------------------------------------------------------------
 app     foo.rb    success            1              0          1     100%
CSV
    end
  end

  def test_stats_error
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh2e(*steep, "stats", "--format=unknown")

      refute_predicate status, :success?, stdout
    end
  end
end
