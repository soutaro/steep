module Steep
  module Drivers
    class PrintInterface
      attr_reader :type_name
      attr_reader :signature_options
      attr_reader :stdout
      attr_reader :stderr

      include Utils::EachSignature

      def initialize(type_name:, signature_options:, stdout:, stderr:)
        @type_name = type_name
        @signature_options = signature_options
        @stdout = stdout
        @stderr = stderr
      end

      def run
        if type_name
          loader = Ruby::Signature::EnvironmentLoader.new()
          signature_options.setup loader: loader

          env = Ruby::Signature::Environment.new()
          loader.load(env: env)

          project = Project.new(environment: env)
          project.reload_signature

          type = Ruby::Signature::Parser.parse_type(type_name)

          case sig = project.signature
          when Project::SignatureLoaded
            check = sig.check
            factory = check.factory

            interface = factory.interface(factory.type(type), private: false)

            stdout.puts "#{type}"
            stdout.puts "- Methods:"
            interface.methods.each do |name, method|
              puts "  - #{Rainbow(name).blue}: #{method}"
            end
            0

          when Project::SignatureHasError
            sig.errors.each do |error|
              case error
              when Interface::Instantiated::InvalidMethodOverrideError
                stdout.puts "😱 #{error.message}"
                error.result.trace.each do |s, t|
                  case s
                  when Interface::Method
                    stdout.puts "  #{s.name}(#{s.type_name}) <: #{t.name}(#{t.type_name})"
                  when Interface::MethodType
                    stdout.puts "  #{s} <: #{t} (#{s.location&.name||"?"}:#{s.location&.start_line||"?"})"
                  else
                    stdout.puts "  #{s} <: #{t}"
                  end
                end
                stdout.puts "  🚨 #{error.result.error.message}"
              when Interface::Instantiated::InvalidIvarOverrideError
                stdout.puts "😱 #{error.message}"
              else
                stdout.puts "😱 #{error.inspect}"
              end
            end

            1
          end
        else
          stderr.puts "Pass a type name to command line"
          1
        end
      end
    end
  end
end
