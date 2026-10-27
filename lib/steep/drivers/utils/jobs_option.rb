module Steep
  module Drivers
    module Utils
      class JobsOption
        attr_accessor :jobs_count, :steep_command, :jobs_count_modifier

        def initialize(jobs_count_modifier: 0)
          @jobs_count_modifier = jobs_count_modifier
        end

        def default_jobs_count
          available_processor_count + jobs_count_modifier
        end

        def available_processor_count
          limit = Concurrent.available_processor_count.floor
          [Concurrent.physical_processor_count, [limit, 1].max].min or raise
        end

        def jobs_count_value
          count = jobs_count || default_jobs_count
          if count >= 1
            count
          else
            1
          end
        end
      end
    end
  end
end
