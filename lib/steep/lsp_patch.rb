# frozen_string_literal: true

# https://github.com/mtsmfm/language_server-protocol-ruby/pull/112
module LanguageServer
  module Protocol
    module Transport
      module Io
        class Reader
          def close
            @io.close
          end unless method_defined?(:close)
        end

        class Writer
          def close
            @io.close
          end unless method_defined?(:close)
        end
      end
    end
  end
end
