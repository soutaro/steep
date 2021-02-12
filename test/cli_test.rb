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

      stdout, _, status = sh(*steep, "check")

      assert_predicate status, :success?
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

      stdout, _, status = sh(*steep, "check")

      refute_predicate status, :success?
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

      stdout, _, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      stdout, _, status = sh(*steep, "check", "--with-expectation=foo.yml")
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

      stdout, _, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, _, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?

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

      stdout, _, status = sh(*steep, "check", "--save-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match /Saved expectations in foo\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, _, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?

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

      stdout, _, status = sh(*steep, "check", "--save-expectation")
      assert_predicate status, :success?
      assert_match /Saved expectations in steep_expectations\.yml\.\.\./, stdout

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, _, status = sh(*steep, "check", "--with-expectation", "foo.rb")
      refute_predicate status, :success?

      assert_match /Expectations unsatisfied:/, stdout
      assert_match /0 expected diagnostics/, stdout
      assert_match /0 unexpected diagnostics/, stdout
      assert_match /1 missing diagnostic/, stdout

      stdout, _, status = sh(*steep, "check", "--with-expectation", "bar.rb")
      assert_predicate status, :success?

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

      stdout, stderr, status = sh(*steep, "check")
      refute_predicate status, :success?
      assert_match /Unexpected error reported./, stdout
      assert_match /ArgumentError: invalid byte sequence in UTF-8/, stderr
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

      (current_dir + "app/lib/foo.rb").write <<RUBY
# steep will type check this file.
1 + ""
RUBY


      r, w = IO.pipe
      pid = spawn(*steep.push("watch", "app/lib"), out: w, chdir: current_dir.to_s)
      w.close

      begin
        output = []

        Thread.new do
          while line = r.gets
            output << line
          end
        end

        sleep 10
      ensure
        Process.kill(:INT, pid)
        Process.waitpid(pid)
        assert_equal 0, $?.exitstatus
      end
    end
  end
end
