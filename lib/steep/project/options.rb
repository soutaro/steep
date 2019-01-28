module Steep
  class Project
    class Options
      attr_accessor :fallback_any_is_error
      attr_accessor :allow_missing_definitions

      def initialize
        self.fallback_any_is_error = false
        self.allow_missing_definitions = true
      end
    end
  end
end
