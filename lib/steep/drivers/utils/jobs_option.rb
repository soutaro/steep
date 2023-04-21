module Steep
  module Drivers
    module Utils
      class JobsOption
        attr_accessor :jobs_count, :steep_command, :jobs_count_modifier

        def initialize(jobs_count_modifier: 0)
          @jobs_count_modifier = jobs_count_modifier
        end

        def default_jobs_count
          Parallel.physical_processor_count + jobs_count_modifier
        end

        def jobs_count_value
          jobs_count || default_jobs_count
        end
      end
    end
  end
end
