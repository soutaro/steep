module Steep
  module Drivers
    class Check
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns

      attr_accessor :dump_all_types

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []

        self.dump_all_types = false
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(command_line_patterns)
        loader.load_signatures()

        type_check(project)

        if self.dump_all_types
          project.targets.each do |target|
            case (status = target.status)
            when Project::Target::TypeCheckStatus
              target.source_files.each_value do |file|
                case (file_status = file.status)
                when Project::SourceFile::TypeCheckStatus
                  output_types(file_status.typing)
                end
              end
            end
          end
        end

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            case (status = target.status)
            when Project::Target::SignatureSyntaxErrorStatus
              printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
              printer.print_syntax_errors(status.errors)
            when Project::Target::SignatureValidationErrorStatus
              printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
              printer.print_semantic_errors(status.errors)
            when Project::Target::TypeCheckStatus
              status.type_check_sources.each do |source_file|
                case source_file.status
                when Project::SourceFile::TypeCheckStatus
                  source_file.errors.select {|error| target.options.error_to_report?(error) }.each do |error|
                    error.print_to stdout
                  end
                when Project::SourceFile::TypeCheckErrorStatus
                  Steep.log_error source_file.status.error
                end
              end
            end
          end
        end

        if project.targets.all? {|target| target.status.is_a?(Project::Target::TypeCheckStatus) && target.no_error? && target.errors.empty? }
          Steep.logger.info "No type error found"
          return 0
        end

        1
      end

      def output_types(typing)
        lines = []

        typing.each_typing do |node, _|
          begin
            type = typing.type_of(node: node)
            lines << [node.loc.expression.source_buffer.name, [node.loc.last_line,node.loc.last_column], [node.loc.first_line, node.loc.column], node, type]
          rescue
            lines << [node.loc.expression.source_buffer.name, [node.loc.last_line,node.loc.last_column], [node.loc.first_line, node.loc.column], node, nil]
          end
        end

        lines.sort {|x,y| y <=> x }.reverse_each do |line|
          source = line[3].loc.expression.source
          stdout.puts "#{line[0]}:(#{line[2].join(",")}):(#{line[1].join(",")}):\t#{line[3].type}:\t#{line[4]}\t(#{source.split(/\n/).first})"
        end
      end
    end
  end
end
