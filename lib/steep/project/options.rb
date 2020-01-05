module Steep
  class Project
    class Options
      attr_accessor :fallback_any_is_error
      attr_accessor :allow_missing_definitions
      attr_accessor :vendored_stdlib_path
      attr_accessor :vendored_gems_path
      attr_reader :libraries

      def initialize
        self.fallback_any_is_error = false
        self.allow_missing_definitions = true
        self.vendored_gems_path = nil
        self.vendored_stdlib_path = nil

        @libraries = []
      end
    end
  end
end
