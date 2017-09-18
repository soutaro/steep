module Steep
  module Drivers
    class Check
      attr_reader :source_paths
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr

      attr_accessor :verbose
      attr_accessor :accept_implicit_any
      attr_accessor :dump_all_types
      attr_accessor :fallback_any_is_error

      attr_reader :labeling

      def initialize(source_paths:, signature_dirs:, stdout:, stderr:)
        @source_paths = source_paths
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr

        self.verbose = false
        self.accept_implicit_any = false
        self.dump_all_types = false
        self.fallback_any_is_error = false

        @labeling = ASTUtils::Labeling.new
      end

      def run
        assignability = TypeAssignability.new do |a|
          each_interface do |signature|
            a.add_signature(signature)
          end
        end

        assignability.errors.each do |error|
          error.puts(stdout)
        end

        sources = []
        each_ruby_source do |source|
          sources << source
        end

        typing = Typing.new

        sources.each do |source|
          stdout.puts "Typechecking #{source.path}..." if verbose
          annotations = source.annotations(block: source.node) || []

          p annotations if verbose

          construction = TypeConstruction.new(
            assignability: assignability,
            annotations: annotations,
            source: source,
            var_types: {},
            self_type: nil,
            block_context: nil,
            module_context: TypeConstruction::ModuleContext.new(
                                                             instance_type: nil,
                                                             module_type: nil,
                                                             const_types: annotations.const_types
            ),
            method_context: nil,
            typing: typing,
          )
          construction.synthesize(source.node)
        end

        if dump_all_types
          lines = []

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

        typing.errors.each do |error|
          next if error.is_a?(Errors::FallbackAny) && !fallback_any_is_error
          stdout.puts error.to_s
        end
      end

      def each_interface
        signature_dirs.each do |path|
          if path.file?
            stdout.puts "Loading signature #{path}..." if verbose
            Parser.parse_signature(path.read).each do |interface|
              yield interface
            end
          end

          if path.directory?
            each_file_in_dir(".rbi", path) do |file|
              stdout.puts "Loading signature #{file}..." if verbose
              Parser.parse_signature(file.read).each do |interface|
                yield interface
              end
            end
          end
        end
      end

      def each_ruby_source
        source_paths.each do |path|
          if path.file?
            stdout.puts "Loading Ruby program #{path}..." if verbose
            yield Source.parse(path.read, path: path.to_s, labeling: labeling)
          end

          if path.directory?
            each_file_in_dir(".rb", path) do |file|
              stdout.puts "Loading Ruby program #{file}..." if verbose
              yield Source.parse(file.read, path: file.to_s, labeling: labeling)
            end
          end
        end
      end

      def each_file_in_dir(suffix, path, &block)
        path.children.each do |child|
          if child.directory?
            each_file_in_dir(suffix, child, &block)
          end

          if child.file? && suffix == child.extname
            yield child
          end
        end
      end
    end
  end
end
