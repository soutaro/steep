module Steep
  class ThreadWaiter
    attr_reader :objects, :queue, :waiter_threads

    def initialize(objects)
      @objects = objects
      @queue = Thread::Queue.new()
      @waiter_threads = Set[].compare_by_identity

      objects.each do |object|
        thread = yield(object)

        waiter_thread = Thread.new(thread) do |thread|
          Thread.current.report_on_exception = false

          begin
            thread.join
          ensure
            queue << [object, thread]
          end
        end

        waiter_threads << waiter_thread
      end
    end

    def wait_one
      unless waiter_threads.empty?
        obj, th = queue.pop()
        waiter_threads.delete(th)
        obj
      end
    end
  end
end
