require_relative "../test_helper"

module CLI
  class CheckfileTest < Minitest::Test
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
        "--gemfile=#{__dir__}/../../Gemfile",
        RUBY_PATH,
        "#{__dir__}/../../exe/steep"
      ]
    end

    def prepare_project(files = {})
      (current_dir + "Steepfile").write(<<-RUBY)
target :app do
  check "lib"
  signature "sig"
end
      RUBY

      (current_dir + "lib").mkdir
      (current_dir + "sig").mkdir

      (current_dir + "lib/error.rb").write(<<-RUBY)
1 + ""
      RUBY
      (current_dir + "lib/success.rb").write(<<-RUBY)
1 + 2
      RUBY

      files.each do |name, content|
        (current_dir + name).write(content)
      end
    end

    def parse_output(output)
      output.lines.map do |line|
        JSON.parse(line, symbolize_names: true)
      end
    end

    def test_no_arg
      in_tmpdir do
        prepare_project()

        stdout = sh!(*steep, "checkfile")

        assert_empty parse_output(stdout)
      end
    end

    def test_ruby_code_error
      in_tmpdir do
        prepare_project()

        stdout = sh!(*steep, "checkfile", "lib/error.rb")
        json = parse_output(stdout)
        assert_equal ["Ruby::UnresolvedOverloading"], json[0][:diagnostics].map {|d| d[:code] }
      end
    end

    def test_ruby_code_success
      in_tmpdir do
        prepare_project()

        stdout = sh!(*steep, "checkfile", "lib/success.rb")

        json = parse_output(stdout)
        assert_empty json[0][:diagnostics].map {|d| d[:code] }
      end
    end

    def test_ruby_code_syntax_error
      in_tmpdir do
        prepare_project({ "lib/syntax_error.rb" =>  "1+" })

        stdout = sh!(*steep, "checkfile", "lib/syntax_error.rb")

        json = parse_output(stdout)
        assert_equal ["Ruby::SyntaxError"], json[0][:diagnostics].map {|d| d[:code] }
      end
    end

    def test_ruby_code_rbs_error
      in_tmpdir do
        prepare_project({ "lib/rbs_error.rb" =>  "class RBSError; end", "sig/rbs_error.rbs" => "class RBSError include Foo end" })

        stdout = sh!(*steep, "checkfile", "lib/rbs_error.rb")

        assert_empty stdout
      end
    end

    def test_ruby_code_rbs_error2
      in_tmpdir do
        prepare_project({ "lib/rbs_error.rb" =>  "class RBSError; end", "sig/rbs_error.rbs" => "class RBSError < Kernel end" })

        stdout, _, _ = sh3(*steep, "checkfile", "lib/rbs_error.rb")

        json = parse_output(stdout)
        json.find {|obj| obj[:path] == "lib/rbs_error.rb" }.tap do |obj|
          assert_equal ["Ruby::UnexpectedError"], obj[:diagnostics].map {|d| d[:code] }
        end
      end
    end

    def test_rbs_success
      in_tmpdir do
        prepare_project({ "sig/test.rbs" => "class TestClass end" })

        stdout = sh!(*steep, "checkfile", "sig/test.rbs")

        json = parse_output(stdout)
        json.find {|obj| obj[:path] == "sig/test.rbs" }.tap do |obj|
          assert_equal [], obj[:diagnostics].map {|d| d[:code] }
        end
      end
    end

    def test_rbs_error
      in_tmpdir do
        prepare_project({ "sig/rbs_error.rbs" => "class RBSError include Foo end" })

        stdout = sh!(*steep, "checkfile", "sig/rbs_error.rbs")

        json = parse_output(stdout)
        json.find {|obj| obj[:path] == "sig/rbs_error.rbs" }.tap do |obj|
          assert_equal ["RBS::UnknownTypeName"], obj[:diagnostics].map {|d| d[:code] }
        end
      end
    end

    def test_rbs_syntax_error
      in_tmpdir do
        prepare_project({ "sig/rbs_error.rbs" => "class RBSError " })

        stdout = sh!(*steep, "checkfile", "sig/rbs_error.rbs")

        json = parse_output(stdout)
        json.find {|obj| obj[:path] == "sig/rbs_error.rbs" }.tap do |obj|
          assert_equal ["RBS::SyntaxError"], obj[:diagnostics].map {|d| d[:code] }
        end
      end
    end

    def test_dirname
      in_tmpdir do
        prepare_project({ "sig/test.rbs" => "class RBSTest end " })

        stdout = sh!(*steep, "checkfile", "sig", "lib")

        json = parse_output(stdout)
        assert_equal ["lib/error.rb", "lib/success.rb", "sig/test.rbs"].sort, json.map {|obj| obj[:path] }.sort
      end
    end

    def test_all_options
      in_tmpdir do
        prepare_project({ "sig/test.rbs" => "class RBSTest end " })

        stdout = sh!(*steep, "checkfile", "--all-ruby", "--all-rbs")

        json = parse_output(stdout)
        assert_equal ["lib/error.rb", "lib/success.rb", "sig/test.rbs"].sort, json.map {|obj| obj[:path] }.sort
      end
    end

    def test_stdin
      in_tmpdir do
        prepare_project()

        stdout = sh!(*steep, "checkfile", "--stdin", "lib/error.rb", stdin_data: { path: "lib/test.rb", content: "1.foo"}.to_json)

        json = parse_output(stdout)
        json.find {|obj| obj[:path] == "lib/test.rb" }.tap do |obj|
          assert_equal ["Ruby::NoMethod"], obj[:diagnostics].map {|d| d[:code] }
        end
        json.find {|obj| obj[:path] == "lib/error.rb" }.tap do |obj|
          assert_equal ["Ruby::UnresolvedOverloading"], obj[:diagnostics].map {|d| d[:code] }
        end
      end
    end
  end
end
