module Steep
  class Project
    attr_reader :targets
    attr_reader :steepfile_path
    attr_reader :base_dir

    def initialize(steepfile_path:, base_dir: nil)
      @targets = []
      @steepfile_path = steepfile_path
      @base_dir = if base_dir
        base_dir
      elsif steepfile_path
        steepfile_path.parent
      else
        raise ArgumentError, "Project#initialize(base_dir:): neither base_dir nor steepfile_path given"
      end

      if steepfile_path and !steepfile_path.absolute?
        raise ArgumentError, "Project#initialize(steepfile_path:): steepfile_path should be absolute path"
      end
    end

    def relative_path(path)
      path.relative_path_from(base_dir)
    rescue ArgumentError
      path
    end

    def absolute_path(path)
      (base_dir + path).cleanpath
    end

    def target_for_source_path(path)
      targets.find do |target|
        target.possible_source_file?(path)
      end
    end

    def targets_for_path(path)
      if target = target_for_source_path(path)
        target
      else
        ts = targets.select {|target| target.possible_signature_file?(path) }
        unless ts.empty?
          ts
        end
      end
    end
  end
end
