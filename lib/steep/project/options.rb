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

      def error_to_report?(error)
        case
        when error.is_a?(Errors::FallbackAny)
          !allow_fallback_any
        when error.is_a?(Errors::MethodDefinitionMissing)
          !allow_missing_definitions
        when error.is_a?(Errors::NoMethod)
          !allow_unknown_method_calls
        when error.is_a?(Errors::UnknownConstantAssigned)
          !allow_unknown_constant_assignment
        else
          true
        end
      end

      def merge!(hash)
        self.allow_fallback_any = hash[:allow_fallback_any] if hash.key?(:allow_fallback_any)
        self.allow_missing_definitions = hash[:allow_missing_definitions] if hash.key?(:allow_missing_definitions)
        self.allow_unknown_constant_assignment = hash[:allow_unknown_constant_assignment] if hash.key?(:allow_unknown_constant_assignment)
        self.allow_unknown_method_calls = hash[:allow_unknown_method_calls] if hash.key?(:allow_unknown_method_calls)
      end
    end
  end
end
