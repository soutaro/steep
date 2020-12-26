module Steep
  module Drivers
    class DiagnosticPrinter
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :buffer

      def initialize(stdout:, buffer:)
        @stdout = stdout
        @buffer = buffer
      end

      def path
        buffer.name
      end

      def color_severity(string, severity:)
        s = Rainbow(string)

        case severity
        when LSP::Constant::DiagnosticSeverity::ERROR
          s.red
        when LSP::Constant::DiagnosticSeverity::WARNING
          s.yellow
        when LSP::Constant::DiagnosticSeverity::INFORMATION
          s.blue
        else
          s
        end
      end

      def severity_message(severity)
        string = case severity
                 when LSP::Constant::DiagnosticSeverity::ERROR
                   "error"
                 when LSP::Constant::DiagnosticSeverity::WARNING
                   "warning"
                 when LSP::Constant::DiagnosticSeverity::INFORMATION
                   "information"
                 when LSP::Constant::DiagnosticSeverity::HINT
                   "hint"
                 end

        color_severity(string, severity: severity)
      end

      def location(diagnostic)
        start = diagnostic[:range][:start]
        Rainbow("#{path}:#{start[:line]+1}:#{start[:character]}").magenta
      end

      def print(diagnostic)
        header, *rest = diagnostic[:message].split(/\n/)

        stdout.puts "#{location(diagnostic)}: [#{severity_message(diagnostic[:severity])}] #{Rainbow(header).underline}"

        rest.each do |message|
          stdout.puts "│ #{message}"
        end
        stdout.puts "│"

        print_source_line(diagnostic)
      end

      def print_source_line(diagnostic)
        start_pos = diagnostic[:range][:start]
        end_pos = diagnostic[:range][:end]

        line = buffer.lines[start_pos[:line]]

        leading = line[0...start_pos[:character]]
        if start_pos[:line] == end_pos[:line]
          subject = line[start_pos[:character]...end_pos[:character]]
          trailing = line[end_pos[:character]...].chomp
        else
          subject = line[start_pos[:character]...].chomp
          trailing = ""
        end

        stdout.puts "└ #{leading}#{color_severity(subject, severity: diagnostic[:severity])}#{trailing}"
        stdout.puts "  #{" " * leading.size}#{"~" * subject.size}"
      end
    end
  end
end
