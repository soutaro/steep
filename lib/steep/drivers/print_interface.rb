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
          project = Project.new()

          signature_dirs.each do |path|
            each_file_in_path(".rbi", path) do |file_path|
              file = Project::SignatureFile.new(path: file_path)
              file.content = file_path.read
              project.signature_files[file_path] = file
            end
          end

          project.reload_signature

          case sig = project.signature
          when Project::SignatureLoaded
            begin
              check = sig.check
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
