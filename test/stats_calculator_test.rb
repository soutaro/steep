require "test_helper"

class StatsCalculatorTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep

  StatsCalculator = Project::StatsCalculator

  def dirs
    @dirs ||= []
  end

  def setup_project(sources)
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      target = project.targets[0]
      sources.each do |path, content|
        case path.extname
        when ".rb"
          target.add_source(path, content)
        when ".rbs"
          target.add_signature(path, content)
        end
      end

      yield project
    end
  end

  def test_stats_success
    setup_project(Pathname("lib/hello.rb") => <<-RUBY) do |project|
1 + 2
(_ = 1) + 2
1 + ""
    RUBY

      calculator = StatsCalculator.new(project: project)

      calculator.calc_stats(project.targets[0],Pathname("lib/hello.rb")).tap do |stats|
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
    setup_project(Pathname("lib/hello.rbs") => <<-RBS, Pathname("lib/hello.rb") => <<-RUBY) do |project|
interface _HelloWorld
    RBS
1+2
    RUBY

      calculator = StatsCalculator.new(project: project)

      calculator.calc_stats(project.targets[0], Pathname("lib/hello.rb")).tap do |stats|
        assert_instance_of StatsCalculator::ErrorStats, stats
        assert_equal :lib, stats.target.name
        assert_equal Pathname("lib/hello.rb"), stats.path
      end
    end
  end
end
