module Steep
  class Project
    attr_reader :targets

    def initialize()
      @targets = []
    end

    def type_of_node(path:, line:, column:)
      source_file = targets.map {|target| target.source_files[path] }.compact[0]

      if source_file
        case (status = source_file.status)
        when SourceFile::TypeCheckStatus
          node = status.source.find_node(line: line, column: column)

          type = begin
            status.typing.type_of(node: node)
          rescue RuntimeError
            AST::Builtin.any_type
          end

          if block_given?
            yield type, node
          else
            type
          end
        end
      end
    end
  end
end
