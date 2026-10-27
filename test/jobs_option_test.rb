require_relative "test_helper"

# @rbs use Steep::*

class JobsOptionTest < Minitest::Test
  include Steep

  JobsOption = Drivers::Utils::JobsOption

  def with_processors(physical:, available:, &block)
    Concurrent.stub(:physical_processor_count, physical) do
      Concurrent.stub(:available_processor_count, available, &block)
    end
  end

  def test_default_jobs_count__no_cpu_limit
    with_processors(physical: 16, available: 32.0) do
      assert_equal 16, JobsOption.new.default_jobs_count
    end
  end

  def test_default_jobs_count__cpu_limit
    with_processors(physical: 16, available: 4.0) do
      assert_equal 4, JobsOption.new.default_jobs_count
    end
  end

  def test_default_jobs_count__fractional_cpu_limit
    with_processors(physical: 16, available: 2.5) do
      assert_equal 2, JobsOption.new.default_jobs_count
    end

    with_processors(physical: 16, available: 0.5) do
      assert_equal 1, JobsOption.new.default_jobs_count
    end
  end

  def test_default_jobs_count__modifier
    with_processors(physical: 16, available: 4.0) do
      assert_equal 3, JobsOption.new(jobs_count_modifier: -1).default_jobs_count
    end

    with_processors(physical: 16, available: 1.0) do
      option = JobsOption.new(jobs_count_modifier: -1)
      assert_equal 0, option.default_jobs_count
      assert_equal 1, option.jobs_count_value
    end
  end

  def test_jobs_count_value__explicit_jobs_count
    with_processors(physical: 16, available: 4.0) do
      option = JobsOption.new
      option.jobs_count = 8
      assert_equal 8, option.jobs_count_value
    end
  end
end
