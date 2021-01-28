module Steep
  module Drivers
    class Validate
      attr_reader :stdout
      attr_reader :stderr

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_signatures()

        type_check(project)

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            case (status = target.status)
            when Project::Target::SignatureErrorStatus
              formatter = Diagnostic::LSPFormatter.new
              diagnostics = status.errors.group_by {|e| e.location.buffer }.transform_values do |errors|
                errors.map {|error| formatter.format(error) }
              end

              diagnostics.each do |buffer, ds|
                printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)
                ds.each do |d|
                  printer.print(d)
                  stdout.puts
                end
              end
            end
          end
        end

        project.targets.all? {|target| target.status.is_a?(Project::Target::TypeCheckStatus) } ? 0 : 1
      end
    end
  end
end
