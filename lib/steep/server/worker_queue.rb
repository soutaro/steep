module Steep
  module Server
    class WorkerQueue
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @urgent_jobs = []
        @jobs = []
        @closed = false
      end

      def push(job, urgent: false)
        @mutex.synchronize do
          raise ClosedQueueError, "The queue is closed" if @closed

          if urgent
            @urgent_jobs << job
          else
            @jobs << job
          end

          @condition.signal
        end

        self
      end

      def <<(job)
        push(job)
      end

      def pop
        @mutex.synchronize do
          loop do
            unless @urgent_jobs.empty?
              return @urgent_jobs.shift
            end

            unless @jobs.empty?
              return @jobs.shift
            end

            return nil if @closed

            @condition.wait(@mutex)
          end
        end
      end

      def close
        @mutex.synchronize do
          @closed = true
          @condition.broadcast
        end

        self
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def empty?
        @mutex.synchronize { @urgent_jobs.empty? && @jobs.empty? }
      end

      def size
        @mutex.synchronize { @urgent_jobs.size + @jobs.size }
      end
    end
  end
end
