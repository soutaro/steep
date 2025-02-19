module Steep
  class PriorityQueue
    attr_reader :items, :cv, :mutex, :closed

    def initialize(*priority)
      @items = {}

      priority.each do |p|
        items[p] = []
      end

      @mutex = Mutex.new
      @cv = ConditionVariable.new()
      @closed = true
    end

    def push(item, priority:)
      mutex.synchronize do
        raise if closed
        items.fetch(priority) << item
        cv.signal
      end
    end

    def pop
      mutex.synchronize do
        loop do
          items.each do |priority, queue|
            unless queue.empty?
              return queue.shift
            end
          end

          if closed
            return
          else
            cv.wait(mutex)
          end
        end
      end
    end

    def close
      mutex.synchronize do
        @closed = true
      end
    end
  end
end
