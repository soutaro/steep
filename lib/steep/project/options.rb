module Steep
  class Project
    class Options
      attr_accessor :fallback_any_is_error
      attr_accessor :allow_missing_definitions
      attr_accessor :no_builtin
      attr_reader :libraries

      def initialize
        self.fallback_any_is_error = false
        self.allow_missing_definitions = true
        self.no_builtin = false
        @libraries = []
      end
    end
  end
end
