module Steep
  module Server
    class ForkLauncher
      attr_reader :typecheck_count
      attr_reader :typecheck_workers
      attr_reader :retired_workers

      def initialize(typecheck_count:)
        @typecheck_count = typecheck_count
        @typecheck_workers = []
        @retired_workers = []
        @forked_count = 0
      end

      def start(service)
        # Compacts the heap so that the workers share more pages with the master
        Process.warmup if Process.respond_to?(:warmup)

        typecheck_count.times do
          name = "typecheck@#{@forked_count}"
          @forked_count += 1
          typecheck_workers << WorkerProcess.fork_typecheck_worker(service, name: name, siblings: retired_workers + typecheck_workers)
        end
      end

      def retire_workers
        retired_workers.concat(typecheck_workers)
        typecheck_workers.clear
      end

      def remove_retired_worker(worker)
        retired_workers.delete(worker)
      end

      def stop
      end
    end
  end
end
