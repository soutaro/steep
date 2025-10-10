require_relative "test_helper"

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
    [
      "bundle",
      "exec",
      "--gemfile=#{__dir__}/../Gemfile",
      RUBY_PATH,
      "#{__dir__}/../exe/steep"
    ]
  end

  def test_version
    in_tmpdir do
      stdout = sh!(*steep, "version")

      assert_equal "#{Steep::VERSION}", stdout.chomp
    end
  end

  def test_jobs_count
    sub_test = -> (command, args) do
      in_tmpdir do
        (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
        EOF

        (current_dir + "foo.rb").write(<<-EOF)
1 + 2
        EOF

        stdout, status = sh(*steep, command, *args)

        assert_predicate status, :success?, stdout
        assert_match(/No type error detected\./, stdout)
      end
    end
    sub_test.call("check", %w(-j 1))
    sub_test.call("check", %w(-j 0))
    sub_test.call("check", %w(-j -1))
  end

  def test_steep_command_option
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      if Gem.win_platform?
        (current_dir + "wrap-steep.bat").write(<<-EOF)
@echo off
ECHO "This is Wrap!"
steep %*
        EOF
        stdout, status = sh(*steep, "check", "--steep-command=./wrap-steep.bat")
      else
        (current_dir + "wrap-steep.sh").write(<<-EOF)
echo "This is Wrap!"
steep $@
        EOF
        FileUtils.chmod("u+x", current_dir + "wrap-steep.sh")
        stdout, status = sh(*steep, "check", "--steep-command=./wrap-steep.sh")
      end

      assert_predicate status, :success?, stdout
      assert_match(/No type error detected\./, stdout)
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
      assert_match(/No type error detected\./, stdout)
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
      assert_match(/Detected 1 problem from 1 file/, stdout)
    end
  end

  def test_erb_check_failure
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "app/views/**/*.erb"
end
      EOF

      (current_dir + "app").mkdir
      (current_dir + "app/views").mkdir
      (current_dir + "app/views/companies").mkdir

      (current_dir + "app/views/companies/_form.html.erb").write(<<-EOF)
<div> Count: <%= 1 + "2" %> </div>
      EOF

      stdout, status = sh(*steep, "check")

      refute_predicate status, :success?, stdout
      assert_match(/Detected 1 problem from 1 file/, stdout)
    end
  end

  def test_erb_check_success
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "app/views/**/*.erb"
end
      EOF

      (current_dir + "app").mkdir
      (current_dir + "app/views").mkdir
      (current_dir + "app/views/companies").mkdir

      (current_dir + "app/views/companies/_form.html.erb").write(<<-EOF)
<div> Count: <%= 1 + 2 %> </div>
      EOF

      stdout, status = sh(*steep, "check")

      assert_predicate status, :success?, stdout
      assert_match(/No type error detected\./, stdout)
    end
  end

  def test_check_failure_with_formatter
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--format", "github")

      refute_predicate status, :success?, stdout
      assert_match(/^::error file=foo.rb,line=1,endLine=1,col=0,endColumn=7/, stdout)
    end
  end

  def test_check_group__target
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end

target :test do
  check "test.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF
      (current_dir + "test.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--group=app")

      assert_match(/^foo.rb:1:0/, stdout)
      refute_match(/^test.rb/, stdout)
    end
  end

  def test_check_group__group
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  group :foo do
    check "foo.rb"
  end

  group :bar do
    check "test.rb"
  end
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF
      (current_dir + "test.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, _ = sh(*steep, "check", "--group=app.foo")

      assert_match(/^foo.rb:1:0/, stdout)
      refute_match(/^test.rb/, stdout)
    end
  end

  def test_check_group__group__target
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  group :foo do
    check "foo.rb"
  end

  group :bar do
    check "bar.rb"
  end

  check "baz.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF
      (current_dir + "bar.rb").write(<<-EOF)
1 + "2"
      EOF
      (current_dir + "baz.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, _ = sh(*steep, "check", "--group=app.foo")

      assert_match(/^foo.rb:1:0/, stdout)
      refute_match(/^bar.rb/, stdout)
      refute_match(/^baz.rb/, stdout)

      stdout, _ = sh(*steep, "check", "--group=app.bar")

      refute_match(/^foo.rb/, stdout)
      assert_match(/^bar.rb:1:0/, stdout)
      refute_match(/^baz.rb/, stdout)

      stdout, _ = sh(*steep, "check", "--group=app.*")

      assert_match(/^foo.rb:1:0/, stdout)
      assert_match(/^bar.rb:1:0/, stdout)
      assert_match(/^baz.rb:1:0/, stdout)

      stdout, _ = sh(*steep, "check", "--group=app")

      refute_match(/^foo.rb/, stdout)
      refute_match(/^bar.rb/, stdout)
      assert_match(/^baz.rb:1:0/, stdout)
    end
  end

  def test_check_failure_severity_level
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
D = Steep::Diagnostic
target :app do
  check "foo.rb"

  configure_code_diagnostics do |hash|
    hash[D::Ruby::NoMethod] = :warning
    hash[D::Ruby::UnresolvedOverloading] = :information
  end
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
1.no_method_error
      EOF

      stdout, status = sh(*steep, "check", "--severity-level=warning")

      refute_predicate status, :success?, stdout
      assert_match(/Detected 1 problem from 1 file/, stdout)

      assert_match(/Ruby::NoMethod/, stdout)
      refute_match(/Ruby::UnresolvedOverloading/, stdout)
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
      assert_match(/Saved expectations in foo\.yml\.\.\./, stdout)

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      assert_predicate status, :success?
      assert_match(/Expectations satisfied:/, stdout)
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
      assert_match(/Saved expectations in foo\.yml\.\.\./, stdout)

      (current_dir + "foo.rb").write(<<-EOF)
1 + "2"
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?, stdout

      assert_match(/Expectations unsatisfied:/, stdout)
      assert_match(/0 expected diagnostics/, stdout)
      assert_match(/1 unexpected diagnostic/, stdout)
      assert_match(/1 missing diagnostic/, stdout)
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
      assert_match(/Saved expectations in foo\.yml\.\.\./, stdout)

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation=foo.yml")
      refute_predicate status, :success?, stdout

      assert_match(/Expectations unsatisfied:/, stdout)
      assert_match(/0 expected diagnostics/, stdout)
      assert_match(/0 unexpected diagnostics/, stdout)
      assert_match(/1 missing diagnostic/, stdout)
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
      assert_match(/Saved expectations in steep_expectations\.yml\.\.\./, stdout)

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      stdout, status = sh(*steep, "check", "--with-expectation", "foo.rb")
      refute_predicate status, :success?, stdout

      assert_match(/Expectations unsatisfied:/, stdout)
      assert_match(/0 expected diagnostics/, stdout)
      assert_match(/0 unexpected diagnostics/, stdout)
      assert_match(/1 missing diagnostic/, stdout)

      stdout, status = sh(*steep, "check", "--with-expectation", "bar.rb")
      assert_predicate status, :success?, stdout

      assert_match(/Expectations satisfied:/, stdout)
      assert_match(/1 expected diagnostic/, stdout)
    end
  end

  def test_check__implicitly_returns_nil
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  implicitly_returns_nil!
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
array = [1,2,3]
array[0] + 1
      EOF

      stdout, status = sh(*steep, "check")

      refute_predicate status, :success?, stdout
      assert_includes stdout, "foo.rb:2:9: [error]"
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
      assert_match(
        /Unexpected error: invalid byte sequence in UTF-8/,
        stdout.force_encoding(Encoding::ASCII_8BIT)
      )
    end
  end

  def test_check_unknown
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "bar.rb").write("")

      stdout, status = sh(*steep, "check", "bar.rb")
      assert_predicate status, :success?, stdout
    end
  end

  def test_check_no_steepfile
    in_tmpdir do
      (current_dir + "foo.rb").write(<<~EOF)
        1 + 2
      EOF

      stdout, stderr, status = sh3(*steep, 'check')

      assert_predicate status, :success?, stdout
      assert_match(/current directory/, stderr)
      assert_match(/steep init/, stderr)
      assert_match(/No type error detected\./, stdout)
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

      skip "Using IO.pipe in spawn is not supported on Windows" if Gem.win_platform?

      r, w = IO.pipe
      pid = spawn(*steep, "watch", "app/lib", out: w, chdir: current_dir.to_s)
      w.close

      output = +""

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

      skip "Using IO.pipe in spawn is not supported on Windows" if Gem.win_platform?

      r, w = IO.pipe
      pid = spawn(*steep.push("watch", "app/models/person.rb"), out: w, chdir: current_dir.to_s)
      w.close

      output = +""

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

      stdout, stderr, status = sh3(*steep, "stats", "--format=table")

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

  def test_binstub_generate
    in_tmpdir do
      (current_dir + "Gemfile").write(<<GEMFILE)
source 'https://rubygems.org'

gem 'steep', path: "#{Bundler.root}"
GEMFILE

      push_env({ "BUNDLE_GEMFILE" => nil }) do
        sh!("bundle", "install") rescue return skip("binstub test requires bundler works")
        stdout = sh!("bundle", "exec", "steep", "binstub")
        assert_equal "Successfully generated executable bin/steep 🎉\n", stdout
        assert_equal <<'EOF', (current_dir + "bin/steep").read
#!/usr/bin/env bash

BINSTUB_DIR=$(cd $(dirname $0); pwd)
GEMFILE=$(readlink -f ${BINSTUB_DIR}/../Gemfile)
ROOT_DIR=$(readlink -f ${BINSTUB_DIR}/..)

STEEP="bundle exec --gemfile=${GEMFILE} steep"

if type "rbenv" > /dev/null 2>&1; then
  STEEP="rbenv exec ${STEEP}"
else
  if type "rvm" > /dev/null 2>&1; then
    if [ -e ${ROOT_DIR}/.ruby-version ]; then
      STEEP="rvm ${ROOT_DIR} do ${STEEP}"
    fi
  fi
fi

exec $STEEP $@
EOF

        assert_equal <<EOM, sh!(RUBY_PATH, "#{__dir__}/../exe/steep", "version")
#{Steep::VERSION}
EOM
      end
    end
  end

  def test_binstub_skip
    in_tmpdir do
      (current_dir + "Gemfile").write(<<GEMFILE)
source 'https://rubygems.org'

gem 'steep', path: "#{Bundler.root}"
GEMFILE

      (current_dir + "bin").mkdir
      (current_dir + "bin/steep").write("# test")

      push_env({ "BUNDLE_GEMFILE" => nil }) do
        sh!("bundle", "install") rescue return skip("binstub test requires bundler works")
        stdout = sh!("bundle", "exec", "steep", "binstub")

        assert_equal "⚠️ bin/steep already exists. Bye! 👋\n", stdout
        assert_equal "# test", (current_dir + "bin/steep").read
      end
    end
  end

  def test_binstub_force
    in_tmpdir do
      (current_dir + "Gemfile").write(<<GEMFILE)
source 'https://rubygems.org'

gem 'steep', path: "#{Bundler.root}"
GEMFILE

      (current_dir + "bin").mkdir
      (current_dir + "bin/steep").write("# test")

      push_env({ "BUNDLE_GEMFILE" => nil }) do
        sh!("bundle", "install") rescue return skip("binstub test requires bundler works")
        stdout = sh!("bundle", "exec", "steep", "binstub", "--force")

        assert_equal "bin/steep already exists. Overwriting...\nSuccessfully generated executable bin/steep 🎉\n", stdout
        refute_equal "# test", (current_dir + "bin/steep").read
      end
    end
  end

  def test_ci_jobs_setup_message
    in_tmpdir do
      (current_dir + "Steepfile").write(<<~RUBY)
        target :app do
          check "foo.rb"
        end
      RUBY

      (current_dir + "foo.rb").write(<<~RUBY)
        1 + 2
      RUBY

      push_env({ "CI" => "true" }) do
        ["check", "checkfile", "stats"].each do |command|
          _, stderr, status = sh3(*steep, command, "foo.rb")
          assert_predicate status, :success?
          assert_match(/CI environment is detected but no `--jobs` option is given./, stderr)
        end

        ["check", "checkfile", "stats"].each do |command|
          _, stderr, status = sh3(*steep, command, "--jobs=1", "foo.rb")

          assert_predicate status, :success?
          refute_match(/CI environment is detected but no `--jobs` option is given./, stderr)
        end
      end
    end
  end
end
