module Steep
  module Drivers
    class Validate
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_accessor :verbose

      def initialize(signature_dirs:, stdout:, stderr:)
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr

        self.verbose = false
      end

      include Utils::EachSignature

      def run
        Steep.logger.level = Logger::DEBUG if verbose

        project = Project.new

        signature_dirs.each do |path|
          each_file_in_path(".rbi", path) do |file_path|
            file = Project::SignatureFile.new(path: file_path)
            file.content = file_path.read
            project.signature_files[file_path] = file
          end
        end

        project.type_check

        case project.signature
        when Project::SignatureHasError
          project.signature.errors.each do |error|
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
        else
          0
        end
      end
    end
  end
end
