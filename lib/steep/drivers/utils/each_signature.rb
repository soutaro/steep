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
          each_ruby_file source_paths do |file|
            begin
              stdout.puts "Loading Ruby program #{file}..." if verbose
              if (source = Source.parse(file.read, path: file.to_s, labeling: labeling))
                yield source
              end
            rescue => exn
              Steep.logger.error "Error occured on parsing #{file}: #{exn.inspect}"
            end
          end
        end

        def each_ruby_file(source_paths)
          source_paths.each do |path|
            if path.file?
              yield path
            end

            if path.directory?
              each_file_in_dir(".rb", path) do |file|
                yield file
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
