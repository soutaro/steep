# frozen_string_literal: true

module LanguageServer
  module Protocol
    module Transport
      module Io
        class Reader
          def close
            @io.close
          end
        end

        class Writer
          def close
            @io.close
          end
        end
      end
    end
  end
end
