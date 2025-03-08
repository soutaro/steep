module Steep
  module Drivers
    class DiagnosticPrinter
      class BaseFormatter
        attr_reader :stdout
        attr_reader :buffer

        def initialize(stdout:, buffer:)
          @stdout = stdout
          @buffer = buffer
        end

        def path
          Pathname(buffer.name)
        end
      end
    end
  end
end
