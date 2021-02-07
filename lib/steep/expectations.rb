module Steep
  class Expectations
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
          expected_set = Set.new(expectation)
          actual_set = Set.new(actual)

          (expected_set + actual_set).sort_by {|a| Expectations.sort_key(a) }.each do |lsp|
            case
            when expected_set.include?(lsp) && actual_set.include?(lsp)
              yield :expected, lsp
            when expected_set.include?(lsp)
              yield :missing, lsp
            when actual_set.include?(lsp)
              yield :unexpected, lsp
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

    def self.sort_key(hash)
      [
        hash.dig(:range, :start, :line),
        hash.dig(:range, :start, :character),
        hash.dig(:range, :end, :line),
        hash.dig(:range, :end, :character),
        hash[:code],
        hash[:severity],
        hash[:message]
      ]
    end

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
      array = []

      diagnostics.each_key.sort.each do |key|
        ds = diagnostics[key]
        array << {
          "file" => key.to_s,
          'diagnostics' => ds.sort_by {|hash| Expectations.sort_key(hash) }
                             .map { |d| Expectations.lsp_to_hash(d) }
        }
      end

      YAML.dump(array)
    end

    def self.load(path:, content:)
      expectations = new()

      YAML.load(content, filename: path.to_s).each do |entry|
        file = Pathname(entry["file"])
        expectations.diagnostics[file] = entry["diagnostics"]
                                           .map {|hash| hash_to_lsp(hash) }
                                           .sort_by! {|h| sort_key(h) }
      end

      expectations
    end

    # Translate hash to LSP Diagnostic message
    def self.hash_to_lsp(hash)
      {
        range: {
          start: {
            line: hash.dig("range", "start", "line") - 1,
            character: hash.dig("range", "start", "character")
          },
          end: {
            line: hash.dig("range", "end", "line") - 1,
            character: hash.dig("range", "end", "character")
          }
        },
        severity: {
          "ERROR" => LSP::Constant::DiagnosticSeverity::ERROR,
          "WARNING" => LSP::Constant::DiagnosticSeverity::WARNING,
          "INFORMATION" => LSP::Constant::DiagnosticSeverity::INFORMATION,
          "HINT" => LSP::Constant::DiagnosticSeverity::HINT
        }[hash["severity"] || "ERROR"],
        message: hash["message"],
        code: hash["code"]
      }
    end

    # Translate LSP diagnostic message to hash
    def self.lsp_to_hash(lsp)
      {
        "range" => {
          "start" => {
            "line" => lsp.dig(:range, :start, :line) + 1,
            "character" => lsp.dig(:range, :start, :character)
          },
          "end" => {
            "line" => lsp.dig(:range, :end, :line) + 1,
            "character" => lsp.dig(:range, :end, :character)
          }
        },
        "severity" => {
          LSP::Constant::DiagnosticSeverity::ERROR => "ERROR",
          LSP::Constant::DiagnosticSeverity::WARNING => "WARNING",
          LSP::Constant::DiagnosticSeverity::INFORMATION => "INFORMATION",
          LSP::Constant::DiagnosticSeverity::HINT => "HINT"
        }[lsp[:severity] || LSP::Constant::DiagnosticSeverity::ERROR],
        "message" => lsp[:message],
        "code" => lsp[:code]
      }
    end
  end
end
