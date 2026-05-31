# frozen_string_literal: true

module Steep
  module Drivers
    class StopServer
      attr_reader :stdout
      attr_reader :stderr

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def run
        Daemon.stop(stderr: stderr)
        0
      end
    end
  end
end
