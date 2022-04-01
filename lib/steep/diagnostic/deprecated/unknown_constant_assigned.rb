Steep.logger.error "Diagnostic `Ruby::UnknownConstantAssigned` is deprecated. Use `Ruby::UnknownConstant` instead."

module Steep
  module Diagnostic
    module Ruby
      class UnknownConstantAssigned < Base
        attr_reader :context
        attr_reader :name

        def initialize(node:, context:, name:)
          const = node.children[0]
          loc = if const
                  const.loc.expression.join(node.loc.name)
                else
                  node.loc.name
                end
          super(node: node, location: loc)
          @context = context
          @name = name
        end

        def header_line
          "Cannot find the declaration of constant `#{name}`"
        end
      end
    end
  end
end
