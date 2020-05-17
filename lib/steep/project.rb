module Steep
  class Project
    attr_reader :targets
    attr_reader :steepfile_path

    def initialize(steepfile_path:)
      @targets = []
      @steepfile_path = steepfile_path

      unless steepfile_path.absolute?
        raise "Project#initialize(steepfile_path:): steepfile_path should be absolute path"
      end
    end

    def base_dir
      steepfile_path.parent
    end

    def relative_path(path)
      path.relative_path_from(base_dir)
    end

    def absolute_path(path)
      (base_dir + path).cleanpath
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
