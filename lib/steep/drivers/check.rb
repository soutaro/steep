module Steep
  module Drivers
    class Check
      attr_reader :source_paths
      attr_reader :signature_options
      attr_reader :stdout
      attr_reader :stderr

      attr_accessor :accept_implicit_any
      attr_accessor :dump_all_types
      attr_accessor :fallback_any_is_error
      attr_accessor :allow_missing_definitions

      attr_reader :labeling

      include Utils::EachSignature

      def initialize(source_paths:, signature_options:, stdout:, stderr:)
        @source_paths = source_paths
        @signature_options = signature_options
        @stdout = stdout
        @stderr = stderr

        self.accept_implicit_any = false
        self.dump_all_types = false
        self.fallback_any_is_error = false
        self.allow_missing_definitions = true
      end

      def options
        Project::Options.new.tap do |opt|
          opt.allow_missing_definitions = allow_missing_definitions
          opt.fallback_any_is_error = fallback_any_is_error
        end
      end

      def run
        loader = Ruby::Signature::EnvironmentLoader.new()
        loader.stdlib_root = nil if signature_options.no_builtin
        signature_options.library_paths.each do |path|
          loader.add(path: path)
        end
        signature_options.signature_paths.each do |path|
          loader.add(path: path)
        end

        env = Ruby::Signature::Environment.new()
        loader.load(env: env)

        project = Project.new(environment: env)

        source_paths.each do |path|
          each_file_in_path(".rb", path) do |file_path|
            file = Project::SourceFile.new(path: file_path, options: options)
            file.content = file_path.read
            project.source_files[file_path] = file
          end
        end

        project.type_check

        case project.signature
        when Project::SignatureLoaded
          output_type_check_result(project)
          project.has_type_error? ? 1 : 0
        when Project::SignatureHasError
          output_signature_errors(project)
          1
        end
      end

      def output_type_check_result(project)
        # @type var project: Project

        if dump_all_types
          project.source_files.each_value do |file|
            lines = []

            if typing = file.typing
              typing.nodes.each_value do |node|
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

        project.source_files.each_value do |file|
          file.errors&.each do |error|
            error.print_to stdout
          end
        end
      end

      def output_signature_errors(project)
        printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
        printer.print_semantic_errors(project.signature.errors)
      end
    end
  end
end
