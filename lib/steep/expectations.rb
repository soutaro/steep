module Steep
  class Expectations
    class Diagnostic < Struct.new(:start_position, :end_position, :severity, :message, :code, keyword_init: true)
      DiagnosticSeverity = LanguageServer::Protocol::Constant::DiagnosticSeverity

      def self.from_hash(hash)
        start_position = {
          line: hash.dig("range", "start", "line") - 1,
          character: hash.dig("range", "start", "character")
        } #: position
        end_position = {
          line: hash.dig("range", "end", "line") - 1,
          character: hash.dig("range", "end", "character")
        } #: position

        severity =
          case hash["severity"] || "ERROR"
          when "ERROR"
            :error
          when "WARNING"
            :warning
          when "INFORMATION"
            :information
          when "HINT"
            :hint
          end #: Diagnostic::LSPFormatter::severity

        Diagnostic.new(
          start_position: start_position,
          end_position: end_position,
          severity: severity,
          message: hash["message"],
          code: hash["code"]
        )
      end

      def self.from_lsp(diagnostic)
        start_position = {
          line: diagnostic.dig(:range, :start, :line),
          character: diagnostic.dig(:range, :start, :character)
        } #: position
        end_position = {
          line: diagnostic.dig(:range, :end, :line),
          character: diagnostic.dig(:range, :end, :character)
        } #: position

        severity =
          case diagnostic[:severity]
          when DiagnosticSeverity::ERROR
            :error
          when DiagnosticSeverity::WARNING
            :warning
          when DiagnosticSeverity::INFORMATION
            :information
          when DiagnosticSeverity::HINT
            :hint
          else
            :error
          end #: Diagnostic::LSPFormatter::severity

        Diagnostic.new(
          start_position: start_position,
          end_position: end_position,
          severity: severity,
          message: diagnostic[:message],
          code: diagnostic[:code]
        )
      end

      def to_hash
        {
          "range" => {
            "start" => {
              "line" => start_position[:line] + 1,
              "character" => start_position[:character]
            },
            "end" => {
              "line" => end_position[:line] + 1,
              "character" => end_position[:character]
            }
          },
          "severity" => severity.to_s.upcase,
          "message" => message,
          "code" => code
        }
      end

      def lsp_severity
        case severity
        when :error
          DiagnosticSeverity::ERROR
        when :warning
          DiagnosticSeverity::WARNING
        when :information
          DiagnosticSeverity::INFORMATION
        when :hint
          DiagnosticSeverity::HINT
        else
          raise
        end
      end

      def to_lsp
        {
          range: {
            start: {
              line: start_position[:line],
              character: start_position[:character]
            },
            end: {
              line: end_position[:line],
              character: end_position[:character]
            }
          },
          severity: lsp_severity,
          message: message,
          code: code
        }
      end

      def sort_key
        [
          start_position[:line],
          start_position[:character],
          end_position[:line],
          end_position[:character],
          code,
          severity,
          message
        ]
      end
    end

    class TestResult
      attr_reader :path
      attr_reader :expectation
      attr_reader :actual

      def initialize(path:, expectation:, actual:)
        @path = path
        @expectation = expectation
        @actual = actual
      end

      def empty?
        actual.empty?
      end

      def satisfied?
        unexpected_diagnostics.empty? && missing_diagnostics.empty?
      end

      def each_diagnostics
        if block_given?
          expected_set = Set.new(expectation) #: Set[Diagnostic]
          actual_set = Set.new(actual) #: Set[Diagnostic]

          (expected_set + actual_set).sort_by(&:sort_key).each do |diagnostic|
            case
            when expected_set.include?(diagnostic) && actual_set.include?(diagnostic)
              yield [:expected, diagnostic]
            when expected_set.include?(diagnostic)
              yield [:missing, diagnostic]
            when actual_set.include?(diagnostic)
              yield [:unexpected, diagnostic]
            end
          end
        else
          enum_for :each_diagnostics
        end
      end

      def expected_diagnostics
        each_diagnostics.select {|type, _| type == :expected }.map {|_, diag| diag }
      end

      def unexpected_diagnostics
        each_diagnostics.select {|type, _| type == :unexpected }.map {|_, diag| diag }
      end

      def missing_diagnostics
        each_diagnostics.select {|type, _| type == :missing }.map {|_, diag| diag }
      end
    end

    LSP = LanguageServer::Protocol

    attr_reader :diagnostics

    def initialize()
      @diagnostics = {}
    end

    def test(path:, diagnostics:)
      TestResult.new(path: path, expectation: self.diagnostics[path] || [], actual: diagnostics)
    end

    def self.empty
      new()
    end

    def to_yaml
      array = [] #: Array[{ "file" => String, "diagnostics" => Array[untyped] }]

      diagnostics.each_key.sort.each do |key|
        ds = diagnostics[key]
        array << {
          "file" => key.to_s,
          'diagnostics' => ds.sort_by(&:sort_key).map(&:to_hash)
        }
      end

      YAML.dump(array)
    end

    def self.load(path:, content:)
      expectations = new()

      YAML.load(content, filename: path.to_s).each do |entry|
        file = Pathname(entry["file"])
        expectations.diagnostics[file] =
          entry["diagnostics"].map {|hash| Diagnostic.from_hash(hash) }.sort_by!(&:sort_key)
      end

      expectations
    end
  end
end
