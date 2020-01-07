module Steep
  module Drivers
    class Annotations
      attr_reader :command_line_patterns
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :labeling

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr

        @command_line_patterns = []
        @labeling = ASTUtils::Labeling.new
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(command_line_patterns)
        loader.load_signatures()

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            target.load_signatures do |_, subtyping, _|
              case (status = target.status)
              when nil     # status set on error cases
                target.source_files.each_value do |file|
                  file.parse(subtyping.factory) do |source|
                    source.each_annotation.sort_by {|node, _| [node.loc.expression.begin_pos, node.loc.expression.end_pos] }.each do |node, annotations|
                      loc = node.loc
                      stdout.puts "#{file.path}:#{loc.line}:#{loc.column}:#{node.type}:\t#{node.loc.expression.source.lines.first}"
                      annotations.each do |annotation|
                        stdout.puts "  #{annotation.location.source}"
                      end
                    end
                  end
                end
              when Project::Target::SignatureSyntaxErrorStatus
                printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
                printer.print_syntax_errors(status.errors)
              when Project::Target::SignatureValidationErrorStatus
                printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
                printer.print_semantic_errors(status.errors)
              end
            end
          end
        end

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
          end
        end

        project.targets.all? {|target| !target.status } ? 0 : 1
      end
    end
  end
end
