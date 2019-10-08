module Steep
  module Drivers
    class PrintInterface
      attr_reader :type_name
      attr_reader :stdout
      attr_reader :stderr

      include Utils::DriverHelper

      def initialize(type_name:, stdout:, stderr:)
        @type_name = type_name
        @stdout = stdout
        @stderr = stderr
      end

      def run
        if type_name
          project = load_config()

          load_signatures(project)
          type_check(project)

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
                type = Ruby::Signature::Parser.parse_type(type_name)
                subtyping = status.subtyping
                factory = subtyping.factory

                interface = factory.interface(factory.type(type), private: false)

                stdout.puts "#{type}"
                stdout.puts "- Methods:"
                interface.methods.each do |name, method|
                  stdout.puts "  - #{Rainbow(name).blue}: #{method}"
                end
              end
            end
          end

          0
        else
          stderr.puts "Pass a type name to command line"
          1
        end
      end
    end
  end
end
