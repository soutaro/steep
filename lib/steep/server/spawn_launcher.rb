module Steep
  module Server
    class SpawnLauncher
      attr_reader :steepfile
      attr_reader :steep_command
      attr_reader :typecheck_count
      attr_reader :interaction
      attr_reader :patterns

      def initialize(steepfile:, steep_command:, typecheck_count:, interaction:, patterns: [])
        @steepfile = steepfile
        @steep_command = steep_command
        @typecheck_count = typecheck_count
        @interaction = interaction
        @patterns = patterns
      end

      def start(master)
        if interaction
          master.attach_worker(
            WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: steepfile, steep_command: steep_command)
          )
        end

        typecheck_count.times do |i|
          master.attach_worker(
            WorkerProcess.start_worker(
              :typecheck,
              name: "typecheck@#{i}",
              steepfile: steepfile,
              steep_command: steep_command,
              index: [typecheck_count, i],
              patterns: patterns
            )
          )
        end
      end

      def stop
      end
    end
  end
end
