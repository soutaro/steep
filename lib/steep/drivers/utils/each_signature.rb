module Steep
  module Drivers
    module Utils
      module EachSignature
        def each_file_in_path(suffix, path)
          if path.file?
            yield path
          end

          if path.directory?
            each_file_in_dir(suffix, path) do |file|
              yield file
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
end
