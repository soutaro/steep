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
