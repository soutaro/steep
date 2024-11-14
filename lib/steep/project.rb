module Steep
  class Project
    attr_reader :targets
    attr_reader :steepfile_path
    attr_reader :base_dir
    attr_accessor :global_options

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

    def group_for_source_path(path)
      path = relative_path(path)
      targets.each do |target|
        ret = target.possible_source_file?(path)
        return ret if ret
      end
      nil
    end

    def group_for_path(path)
      group_for_source_path(path) || group_for_signature_path(path)
    end

    def group_for_signature_path(path)
      relative = relative_path(path)
      targets.each do
        ret = _1.possible_signature_file?(relative)
        return ret if ret
      end
      nil
    end

    def target_for_source_path(path)
      case group = group_for_source_path(path)
      when Target
        group
      when Group
        group.target
      end
    end

    def target_for_signature_path(path)
      case group = group_for_signature_path(path)
      when Target
        group
      when Group
        group.target
      end
    end

    def target_for_path(path)
      target_for_source_path(path) || target_for_signature_path(path)
    end
  end
end
