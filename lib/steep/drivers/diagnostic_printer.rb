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
        Pathname(buffer.name)
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
                 else
                  raise
                 end

        color_severity(string, severity: severity)
      end

      def location(diagnostic)
        start = diagnostic[:range][:start]
        Rainbow("#{path}:#{start[:line]+1}:#{start[:character]}").magenta
      end

      def print(diagnostic, prefix: "", source: true)
        header, *rest = diagnostic[:message].split(/\n/)

        stdout.puts "#{prefix}#{location(diagnostic)}: [#{severity_message(diagnostic[:severity])}] #{Rainbow(header).underline}"

        unless rest.empty?
          rest.each do |message|
            stdout.puts "#{prefix}│ #{message}"
          end
        end

        if diagnostic[:code]
          stdout.puts "#{prefix}│" unless rest.empty?
          stdout.puts "#{prefix}│ Diagnostic ID: #{diagnostic[:code]}"
        end

        stdout.puts "#{prefix}│"

        if source
          print_source_line(diagnostic, prefix: prefix)
        else
          stdout.puts "#{prefix}└ (no source code available)"
          stdout.puts "#{prefix}"
        end
      end

      def print_source_line(diagnostic, prefix: "")
        start_pos = diagnostic[:range][:start]
        end_pos = diagnostic[:range][:end]

        line = buffer.lines[start_pos[:line]]

        leading = line[0...start_pos[:character]] || ""
        if start_pos[:line] == end_pos[:line]
          subject = line[start_pos[:character]...end_pos[:character]] || ""
          trailing = (line[end_pos[:character]...] || "").chomp
        else
          subject = (line[start_pos[:character]...] || "").chomp
          trailing = ""
        end

        unless subject.valid_encoding?
          subject.scrub!
        end

        stdout.puts "#{prefix}└ #{leading}#{color_severity(subject, severity: diagnostic[:severity])}#{trailing}"
        stdout.puts "#{prefix}  #{" " * leading.size}#{"~" * subject.size}"
      end
    end
  end
end
