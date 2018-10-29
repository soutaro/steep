module Steep
  module Drivers
    class PrintInterface
      attr_reader :type_name
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr

      include Utils::EachSignature

      def initialize(type_name:, signature_dirs:, stdout:, stderr:)
        @type_name = type_name
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr
      end

      def run
        if type_name
          type = Parser.parse_type(type_name)

          env = AST::Signature::Env.new

          each_signature(signature_dirs, false) do |signature|
            env.add signature
          end

          begin
            builder = Interface::Builder.new(signatures: env)
            check = Subtyping::Check.new(builder: builder)

            interface = check.resolve(type)

            stdout.puts "#{type}"
            stdout.puts "- Instance variables:"
            interface.ivars.each do |name, type|
              puts "  - #{name}: #{type}"
            end
            stdout.puts "- Methods:"
            interface.methods.each do |name, method|
              puts "  - #{Rainbow(name).blue}:"
              method.types.each do |method_type|
                loc = if method_type.location
                        "#{method_type.location.buffer.name}:#{method_type.location.to_s}"
                      else
                        "no location"
                      end
                puts "    - #{Rainbow(method_type.to_s).red} (#{loc})"
              end
            end
            0
          rescue Steep::Subtyping::Check::CannotResolveError
            stderr.puts "🤔 #{Rainbow(type.to_s).red} cannot be resolved to interface"
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
