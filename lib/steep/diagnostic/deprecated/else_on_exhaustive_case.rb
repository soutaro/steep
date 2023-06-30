Steep.logger.error "Diagnostic `Ruby::ElseOnExhaustiveCase` is deprecated. Use `Ruby::UnreachableBranch` instead."

module Steep
  module Diagnostic
    module Ruby
      class ElseOnExhaustiveCase < Base
        attr_reader :type

        def initialize(node:, type:)
          super(node: node)
          @type = type
        end

        def header_line
          "The branch is unreachable because the condition is exhaustive"
        end
      end
    end
  end
end
