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
        file_loader = Services::FileLoader.new(base_dir: project.base_dir)

        any_error = false

        project.targets.each do |target|
          controller = Services::SignatureService.load_from(target.new_env_loader(project: project))

          changes = file_loader.load_changes(target.signature_pattern, changes: {})
          controller.update(changes)

          errors =
            Steep.measure "Validation" do
              case controller.status
              when Services::SignatureService::SyntaxErrorStatus, Services::SignatureService::AncestorErrorStatus
                controller.status.diagnostics
              when Services::SignatureService::LoadedStatus
                factory = AST::Types::Factory.new(builder: controller.latest_builder)
                builder = Interface::Builder.new(factory)
                check = Subtyping::Check.new(builder: builder)
                Signature::Validator.new(checker: check).tap {|v| v.validate() }.each_error.to_a
              else
                raise
              end
            end

          any_error ||= !errors.empty?

          formatter = Diagnostic::LSPFormatter.new({})
          diagnostics = errors.group_by {|e| e.location&.buffer }.transform_values do |errors|
            errors.map {|error| formatter.format(error) }
          end

          diagnostics.each do |buffer, ds|
            if buffer
              printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)
              ds.each do |d|
                printer.print(d)
                stdout.puts
              end
            end
          end
        end

        any_error ? 1 : 0
      end
    end
  end
end
