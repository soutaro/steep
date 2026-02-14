require_relative "test_helper"

class DaemonTest < Minitest::Test
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

  def setup
    system(*steep, "server", "stop", out: File::NULL, err: File::NULL)
  end

  def teardown
    system(*steep, "server", "stop", out: File::NULL, err: File::NULL)
  end

  def test_daemon_socket_path
    project_id = Digest::MD5.hexdigest(Dir.pwd)[0, 8]
    expected_socket = File.join(Dir.tmpdir, "steep-server", "steep-#{project_id}.sock")

    assert_equal expected_socket, Steep::Daemon.socket_path
  end

  def test_daemon_not_running_initially
    refute Steep::Daemon.running?, "Daemon should not be running initially"
  end

  def test_start_server_command
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1 + 2
      EOF

      output, status = sh(*steep, "server", "start", err: [:child, :out])
      assert_predicate status, :success?, "server start should succeed"
      assert_match(/Steep server started/, output)

      sleep 2

      output, status = sh(*steep, "server", "stop", err: [:child, :out])
      assert_predicate status, :success?, "server stop should succeed"
      assert_match(/Steep server stopped/, output)
    end
  end

  def test_start_server_when_already_running
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      output1, status1 = sh(*steep, "server", "start", err: [:child, :out])
      assert_predicate status1, :success?
      assert_match(/Steep server started/, output1)
      sleep 2

      output2, status2 = sh(*steep, "server", "start", err: [:child, :out])
      assert_predicate status2, :success?
      assert_match(/already running/, output2)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end

  def test_stop_server_when_not_running
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      output, status = sh(*steep, "server", "stop", err: [:child, :out])
      assert_match(/not running|cleaned up stale files/, output)
    end
  end

  def test_check_with_daemon
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
  check "bar.rb"
  signature "sig"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1 + 2
      EOF

      (current_dir + "bar.rb").write(<<-EOF)
# @type var y: String
y = "hello"
      EOF

      (current_dir + "sig").mkdir

      sh!(*steep, "server", "start", err: [:child, :out])
      sleep 3

      stdout, status = sh(*steep, "check")
      assert_predicate status, :success?, "check should succeed with daemon"
      assert_match(/server mode/, stdout)
      assert_match(/No type error detected/, stdout)

      stdout2, status2 = sh(*steep, "check")
      assert_predicate status2, :success?
      assert_match(/server mode/, stdout2)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end

  def test_check_falls_back_without_daemon
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
1 + 2
      EOF

      system(*steep, "server", "stop", out: File::NULL, err: File::NULL)

      stdout, status = sh(*steep, "check")
      assert_predicate status, :success?, "check should succeed without daemon"
      refute_match(/server mode/, stdout)
      assert_match(/No type error detected/, stdout)
    end
  end

  def test_daemon_detects_file_changes
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
  signature "sig"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1
      EOF

      (current_dir + "sig").mkdir

      sh!(*steep, "server", "start", err: [:child, :out])
      sleep 3

      stdout1, status1 = sh(*steep, "check")
      assert_predicate status1, :success?
      assert_match(/No type error detected/, stdout1)

      (current_dir + "foo.rb").write(<<-EOF)
x = "string"
      EOF

      sleep 0.5

      stdout2, status2 = sh(*steep, "check")
      assert_match(/server mode/, stdout2)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end

  def test_restart_server_command
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1 + 2
      EOF

      output1, status1 = sh(*steep, "server", "start", err: [:child, :out])
      assert_predicate status1, :success?, "server start should succeed"
      assert_match(/Steep server started/, output1)
      sleep 2

      output2, status2 = sh(*steep, "server", "restart", err: [:child, :out])
      assert_predicate status2, :success?, "server restart should succeed"
      assert_match(/Steep server stopped/, output2)
      assert_match(/Steep server started/, output2)
      sleep 2

      stdout, status = sh(*steep, "check")
      assert_predicate status, :success?
      assert_match(/server mode/, stdout)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end

  def test_server_help
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      output1, status1 = sh(*steep, "server", "--help", err: [:child, :out])
      assert_predicate status1, :success?, "server --help should succeed"
      assert_match(/Usage: steep server/, output1)
      assert_match(/Available subcommands:/, output1)
      assert_match(/start/, output1)
      assert_match(/stop/, output1)
      assert_match(/restart/, output1)

      output2, status2 = sh(*steep, "server", err: [:child, :out])
      assert_predicate status2, :success?, "server without subcommand should show help"
      assert_match(/Usage: steep server/, output2)
      assert_match(/Available subcommands:/, output2)
    end
  end

  def test_check_waits_for_daemon_warmup
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1 + 2
      EOF

      pid = spawn(*steep, "server", "start", out: File::NULL, err: File::NULL)
      Process.detach(pid)

      sleep 0.5

      stdout, status = sh(*steep, "check")
      assert_predicate status, :success?, "check should succeed"
      assert_match(/No type error detected/, stdout)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end

  def test_check_with_no_daemon_flag
    in_tmpdir do
      (current_dir + "Steepfile").write(<<-EOF)
target :app do
  check "foo.rb"
end
      EOF

      (current_dir + "foo.rb").write(<<-EOF)
# @type var x: Integer
x = 1 + 2
      EOF

      sh!(*steep, "server", "start", err: [:child, :out])
      sleep 2

      stdout, status = sh(*steep, "check", "--no-daemon")
      assert_predicate status, :success?, "check should succeed with --no-daemon"
      refute_match(/server mode/, stdout)
      assert_match(/No type error detected/, stdout)

      sh!(*steep, "server", "stop", err: [:child, :out])
    end
  end
end
