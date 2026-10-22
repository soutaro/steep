module Steep
  module Server
    module WorkerLauncher
      def self.create(steepfile:, steep_command:, typecheck_count:)
        if !steep_command && Steep.can_fork?
          ForkLauncher.new(typecheck_count: typecheck_count)
        else
          SpawnLauncher.new(steepfile: steepfile, steep_command: steep_command, typecheck_count: typecheck_count)
        end
      end
    end
  end
end
