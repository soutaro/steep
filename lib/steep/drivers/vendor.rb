module Steep
  module Drivers
    class Vendor
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :stdin

      attr_accessor :vendor_dir
      attr_accessor :clean_before

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin

        @clean_before = false
        @vendor_dir = nil
      end

      def run
        stdout.puts "`steep vendor` is deprecated. Use `rbs vendor` command directly"

        0
      end
    end
  end
end
