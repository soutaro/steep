require_relative "test_helper"

class StatsCalculatorTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep

  StatsCalculator = Services::StatsCalculator
  ContentChange = Services::ContentChange

  def dirs
    @dirs ||= []
  end

  def setup_project()
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      yield Services::TypeCheckService.new(project: project)
    end
  end

  def test_count_calls
    setup_project() do |service|
      service.update(changes: {
        Pathname("lib/hello.rb") => [ContentChange.string(<<~RUBY)]
          1 + 2
          (_ = 1) + 2
          1 + ""
        RUBY
      })

      file = service.typecheck_source(path: Pathname("lib/hello.rb"), target: service.project.targets[0]) or raise
      typing = file.typing or raise

      assert_equal({ typed_calls: 1, untyped_calls: 1, error_calls: 1 }, StatsCalculator.count_calls(typing))
    end
  end

  def test_stats_as_json
    setup_project() do |service|
      target = service.project.targets[0]

      stats = StatsCalculator::SuccessStats.new(target: target, path: Pathname("lib/hello.rb"), typed_calls_count: 3, untyped_calls_count: 2, error_calls_count: 1)
      assert_equal(
        { type: "success", target: "lib", path: "lib/hello.rb", typed_calls: 3, untyped_calls: 2, error_calls: 1, total_calls: 6 },
        stats.as_json
      )

      stats = StatsCalculator::ErrorStats.new(target: target, path: Pathname("lib/hello.rb"))
      assert_equal({ type: "error", target: "lib", path: "lib/hello.rb" }, stats.as_json)
    end
  end
end
