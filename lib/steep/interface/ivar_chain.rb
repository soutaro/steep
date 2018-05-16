module Steep
  module Interface
    class IvarChain
      attr_reader :type
      attr_reader :parent

      def initialize(type:, parent: nil)
        @type = type
        @parent = parent
      end

      def ==(other)
        other.is_a?(IvarChain) &&
          type == type &&
          parent == parent
      end

      def subst(s)
        self.class.new(
          type: type.subst(s),
          parent: parent&.subst(s)
        )
      end
    end
  end
end
