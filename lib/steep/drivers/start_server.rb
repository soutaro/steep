# frozen_string_literal: true

module Steep
  module Drivers
    class StartServer
      attr_reader :stdout
      attr_reader :stderr

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def run
        Daemon.start(stderr: stderr) ? 0 : 1
      end
    end
  end
end
