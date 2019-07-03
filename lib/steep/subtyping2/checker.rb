module Steep
  module Subtyping2
    class Checker
      attr_reader :builder
      attr_reader :cache

      def initialize(builder:)
        @builder = builder
        @cache = {}
      end


    end
  end
end
