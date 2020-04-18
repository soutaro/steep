module Steep
  class Project
    class Options
      attr_accessor :allow_fallback_any
      attr_accessor :allow_missing_definitions
      attr_accessor :allow_unknown_constant_assignment
      attr_accessor :allow_unknown_method_calls
      attr_accessor :vendored_stdlib_path
      attr_accessor :vendored_gems_path
      attr_reader :libraries

      def initialize
        apply_default_typing_options!
        self.vendored_gems_path = nil
        self.vendored_stdlib_path = nil

        @libraries = []
      end

      def apply_default_typing_options!
        self.allow_fallback_any = true
        self.allow_missing_definitions = true
        self.allow_unknown_constant_assignment = false
        self.allow_unknown_method_calls = false
      end

      def apply_strict_typing_options!
        self.allow_fallback_any = false
        self.allow_missing_definitions = false
        self.allow_unknown_constant_assignment = false
        self.allow_unknown_method_calls = false
      end

      def apply_lenient_typing_options!
        self.allow_fallback_any = true
        self.allow_missing_definitions = true
        self.allow_unknown_constant_assignment = true
        self.allow_unknown_method_calls = true
      end
    end
  end
end
