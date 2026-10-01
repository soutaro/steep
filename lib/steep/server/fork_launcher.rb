module Steep
  module Server
    class ForkLauncher
      attr_reader :typecheck_count
      attr_reader :typecheck_workers

      def initialize(typecheck_count: [Etc.nprocessors - 1, 1].max)
        @typecheck_count = typecheck_count
        @typecheck_workers = []
      end

      def shares_environment?
        true
      end

      def start(service)
        # Compacts the heap so that the workers share more pages with the master
        Process.warmup if Process.respond_to?(:warmup)

        typecheck_count.times do |i|
          typecheck_workers << WorkerProcess.fork_typecheck_worker(service, name: "typecheck@#{i}", siblings: typecheck_workers)
        end
      end

      def stop
      end
    end
  end
end
