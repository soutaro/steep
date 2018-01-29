module Steep
  module Drivers
    module Utils
      module EachSignature
        def each_signature(signature_dirs, verbose)
          signature_dirs.each do |path|
            if path.file?
              stderr.puts "Loading signature #{path}..." if verbose
              Parser.parse_signature(path.read, name: path).each do |signature|
                yield signature
              end
            end

            if path.directory?
              each_file_in_dir(".rbi", path) do |file|
                stderr.puts "Loading signature #{file}..." if verbose
                Parser.parse_signature(file.read, name: file).each do |signature|
                  yield signature
                end
              end
            end
          end
        end

        def each_ruby_source(source_paths, verbose)
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
end
