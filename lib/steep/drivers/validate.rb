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

        any_error = false

        project.targets.each do |target|
          loader = Project::Target.construct_env_loader(options: target.options)
          controller = SignatureController.load_from(loader)

          changes = target.signature_files.each.with_object({}) do |(path, file), changes|
            changes[path] = [
              Services::ContentChange.new(range: nil, text: file.content)
            ]
          end
          controller.update(changes)

          errors = case controller.status
                   when SignatureController::ErrorStatus
                     controller.status.diagnostics
                   when SignatureController::LoadedStatus
                     check = Subtyping::Check.new(factory: AST::Types::Factory.new(builder: controller.current_builder))
                     Signature::Validator.new(checker: check).tap {|v| v.validate() }.each_error.to_a
                   end

          any_error ||= !errors.empty?

          formatter = Diagnostic::LSPFormatter.new
          diagnostics = errors.group_by {|e| e.location.buffer }.transform_values do |errors|
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

        any_error ? 1 : 0
      end
    end
  end
end
