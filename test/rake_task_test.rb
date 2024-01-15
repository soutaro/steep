require_relative "test_helper"

require_relative "../lib/steep/rake_task"

require "minitest/mock"

class RakeTaskTest < Minitest::Test
  def test_task_configuration
    configuration = Steep::RakeTask::TaskConfiguration.new

    configuration.check.severity_level = :error
    configuration.watch.verbose

    assert_raises(NoMethodError) do
      configuration.missing_command.verbose
    end

    assert_equal ["--severity-level", "error"], configuration.options(:check)
    assert_equal ["--verbose"], configuration.options(:watch)
    assert_equal [], configuration.options(:stats)
  end

  def test_define_task_with_options
    cli = mock_cli(expecting: %w[check --severity-level error])

    setup_rake_tasks!(cli) do |task|
      task.check.severity_level = :error
    end

    Rake::Task["steep:check"].invoke
  end

  def test_rake_arguments
    cli = mock_cli(expecting: %w[check --severity-level error])

    setup_rake_tasks!(cli)

    Rake::Task["steep:check"].invoke("--severity-level", "error")
  end

  def test_help_task
    cli = mock_cli(expecting: %w[--help])

    setup_rake_tasks!(cli)

    Rake::Task["steep:help"].invoke
  end

  def test_default_task
    cli = mock_cli(expecting: %w[check --verbose])

    setup_rake_tasks!(cli) do |task|
      task.check.verbose
    end

    Rake::Task["steep"].invoke
  end

  def test_skipped_commands
    setup_rake_tasks!

    assert Rake::Task.task_defined?("steep:help")

    refute Rake::Task.task_defined?("steep:langserver")
  end

  private

  def setup_rake_tasks!(cli_runner = nil, &block)
    Rake::Task.clear

    Steep::RakeTask.new(:steep, cli_runner, &block)
  end

  def mock_cli(expecting:)
    cli = Minitest::Mock.new

    cli.expect(:run, nil, [expecting])

    lambda do |arguments|
      cli.run(arguments)

      0
    end
  end
end
