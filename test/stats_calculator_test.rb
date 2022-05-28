require_relative "test_helper"

class StatsCalculatorTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep

  StatsCalculator = Services::StatsCalculator
  ContentChange = Services::ContentChange

  def dirs
    @dirs ||= []
  end

  def setup_project()
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      yield Services::TypeCheckService.new(project: project)
    end
  end

  def test_stats_success
    setup_project() do |service|
      service.update_and_check(
        changes: {
          Pathname("lib/hello.rb") => [ContentChange.string(<<RUBY)]
1 + 2
(_ = 1) + 2
1 + ""
RUBY
        },
        assignment: Services::PathAssignment.all
      ) {}

      calculator = StatsCalculator.new(service: service)

      target = service.project.targets[0]

      calculator.calc_stats(target, file: service.source_files[Pathname("lib/hello.rb")]).tap do |stats|
        assert_instance_of StatsCalculator::SuccessStats, stats
        assert_equal :lib, stats.target.name
        assert_equal Pathname("lib/hello.rb"), stats.path
        assert_equal 1, stats.typed_calls_count
        assert_equal 1, stats.untyped_calls_count
        assert_equal 1, stats.typed_calls_count
      end
    end
  end

  def test_stats_syntax_error
    setup_project do |service|
      service.update_and_check(
        changes: {
          Pathname("sig/hello.rbs") => [ContentChange.string(<<-RBS)],
interface _HelloWorld
          RBS
          Pathname("lib/hello.rb") => [ContentChange.string(<<-RUBY)]
1+2
          RUBY
        },
        assignment: Services::PathAssignment.all
      ) {}

      calculator = StatsCalculator.new(service: service)

      target = service.project.targets[0]

      calculator.calc_stats(target, file: service.source_files[Pathname("lib/hello.rb")]).tap do |stats|
        assert_instance_of StatsCalculator::ErrorStats, stats
        assert_equal :lib, stats.target.name
        assert_equal Pathname("lib/hello.rb"), stats.path
      end
    end
  end
end
