module Steep
  class Project
    class Options
      PathOptions = _ = Struct.new(:core_root, :stdlib_root, :repo_paths, keyword_init: true) do
        # @implements PathOptions

        def customized_stdlib?
          stdlib_root != nil
        end

        def customized_core?
          core_root != nil
        end
      end

      attr_reader :libraries
      attr_accessor :paths
      attr_accessor :collection_config_path

      def initialize
        @paths = PathOptions.new(repo_paths: [])
        @libraries = []
      end

      def collection_lock_path
        if collection_config_path
          RBS::Collection::Config.to_lockfile_path(collection_config_path)
        end
      end

      def load_collection_lock(force: false)
        @collection_lock = nil if force
        @collection_lock ||=
          if collection_config_path && collection_lock_path
            case
            when !collection_config_path.file?
              collection_config_path
            when !collection_lock_path.file?
              collection_lock_path
            else
              begin
                content = YAML.load_file(collection_lock_path)
                lock_file = RBS::Collection::Config::Lockfile.from_lockfile(lockfile_path: collection_lock_path, data: content)
                lock_file.check_rbs_availability!
                lock_file
              rescue YAML::SyntaxError, RBS::Collection::Config::CollectionNotAvailable => exn
                exn
              end
            end
          end
      end

      def collection_lock
        case config = load_collection_lock()
        when RBS::Collection::Config::Lockfile
          config
        else
          nil
        end
      end
    end
  end
end
