module Steep
  module Server
    class SpawnLauncher
      attr_reader :steepfile
      attr_reader :steep_command
      attr_reader :typecheck_count
      attr_reader :patterns
      attr_reader :typecheck_workers

      def initialize(steepfile:, steep_command:, typecheck_count: [Etc.nprocessors - 1, 1].max, patterns: [])
        @steepfile = steepfile
        @steep_command = steep_command
        @typecheck_count = typecheck_count
        @patterns = patterns
        @typecheck_workers = []
      end

      def start(_service)
        typecheck_count.times do |i|
          typecheck_workers << WorkerProcess.start_worker(
            :typecheck,
            name: "typecheck@#{i}",
            steepfile: steepfile,
            steep_command: steep_command,
            index: [typecheck_count, i],
            patterns: patterns
          )
        end
      end

      def stop
      end
    end
  end
end
