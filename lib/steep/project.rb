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

    def relative_path(orig_path)
      path = if Gem.win_platform?
               path_str = URI.decode_www_form_component(
                 orig_path.to_s.delete_prefix("/")
               )
               unless path_str.start_with?(%r{[a-z]:/}i)
                 # FIXME: Sometimes drive letter is missing, taking from base_dir
                 path_str = base_dir.to_s.split("/")[0] + "/" + path_str
               end
               Pathname.new(
                 path_str
               )
             else
               orig_path
             end
      path.relative_path_from(base_dir)
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
        [target, []]
      else
        [
          nil,
          targets.select do |target|
            target.possible_signature_file?(path)
          end
        ]
      end
    end
  end
end
