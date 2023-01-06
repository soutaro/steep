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
      attr_accessor :collection_lock

      def initialize
        @paths = PathOptions.new(repo_paths: [])
        @libraries = []
      end
    end
  end
end
