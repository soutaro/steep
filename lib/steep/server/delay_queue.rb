module Steep
  module Server
    class DelayQueue
      attr_reader :delay, :thread, :queue, :last_task

      def initialize(delay:)
        @delay = delay

        @queue = Thread::Queue.new

        @thread = Thread.new do
          while (scheduled_at, proc = queue.pop)
            diff = scheduled_at - Time.now
            case
            when diff > 0.1
              sleep diff
            when diff > 0
              while Time.now < scheduled_at
                # nop
                sleep 0
              end
            end

            if proc.equal?(last_task)
              unless @cancelled
                proc[]
              end
            end
          end
        end
      end

      def cancel
        @cancelled = true
        queue.clear()
      end

      def execute(&block)
        @last_task = block
        scheduled_at = Time.now + delay
        queue << [scheduled_at, block]
      end
    end
  end
end
