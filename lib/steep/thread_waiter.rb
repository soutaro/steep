module Steep
  class ThreadWaiter
    attr_reader :queue, :waiter_threads

    def initialize(objects = nil)
      @queue = Thread::Queue.new()
      @waiter_threads = Set[].compare_by_identity

      if objects
        objects.each do |object|
          thread = yield(object)
          self << thread
        end
      end
    end

    def <<(thread)
      waiter_thread = Thread.new(thread) do |thread|
        # @type var thread: Thread

        Thread.current.report_on_exception = false

        begin
          thread.join
        ensure
          queue << thread
        end
      end

      waiter_threads << waiter_thread

      self
    end

    def wait_one
      unless waiter_threads.empty?
        th = queue.pop() or raise
        waiter_threads.delete(th)
        th
      end
    end
  end
end
