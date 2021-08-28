module Steep
  class Project
    class Options
      PathOptions = Struct.new(:core_root, :stdlib_root, :repo_paths, keyword_init: true) do
        def customized_stdlib?
          stdlib_root != nil
        end

        def customized_core?
          core_root != nil
        end
      end

      attr_accessor :allow_fallback_any
      attr_accessor :allow_missing_definitions
      attr_accessor :allow_unknown_constant_assignment
      attr_accessor :allow_unknown_method_calls

      attr_reader :libraries
      attr_accessor :paths

      def initialize
        apply_default_typing_options!
        @paths = PathOptions.new(repo_paths: [])
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
        when error.is_a?(Diagnostic::Ruby::FallbackAny)
          !allow_fallback_any
        when error.is_a?(Diagnostic::Ruby::MethodDefinitionMissing)
          !allow_missing_definitions
        when error.is_a?(Diagnostic::Ruby::NoMethod)
          !allow_unknown_method_calls
        when error.is_a?(Diagnostic::Ruby::UnknownConstantAssigned)
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
