module Steep
  class Project
    class Group
      attr_reader :name
      attr_reader :source_pattern
      attr_reader :signature_pattern
      attr_reader :target
      attr_reader :code_diagnostics_config

      def initialize(target, name, source_pattern, signature_pattern, code_diagnostics_config)
        @target = target
        @name = name
        @source_pattern = source_pattern
        @signature_pattern = signature_pattern
        @code_diagnostics_config = code_diagnostics_config
      end

      def project
        target.project
      end

      def possible_source_file?(path)
        source_pattern =~ path
      end

      def possible_signature_file?(path)
        signature_pattern =~ path
      end
    end
  end
end
