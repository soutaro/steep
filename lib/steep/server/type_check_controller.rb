module Steep
  module Server
    class TypeCheckController
      class Request
        attr_reader :guid
        attr_reader :library_paths
        attr_reader :signature_paths
        attr_reader :code_paths
        attr_reader :priority_paths
        attr_reader :checked_paths
        attr_reader :work_done_progress
        attr_reader :started_at
        attr_accessor :needs_response

        def initialize(guid:, progress:)
          @guid = guid
          @library_paths = Set[]
          @signature_paths = Set[]
          @code_paths = Set[]
          @priority_paths = Set[]
          @checked_paths = Set[]
          @work_done_progress = progress
          @started_at = Time.now
          @needs_response = false
        end

        def uri(path)
          Steep::PathHelper.to_uri(path)
        end

        def as_json(assignment:)
          {
            guid: guid,
            library_uris: library_paths.grep(assignment).map {|path| uri(path).to_s },
            signature_uris: signature_paths.grep(assignment).map {|path| uri(path).to_s },
            code_uris: code_paths.grep(assignment).map {|path| uri(path).to_s },
            priority_uris: priority_paths.map {|path| uri(path).to_s }
          }
        end

        def total
          library_paths.size + signature_paths.size + code_paths.size
        end

        def percentage
          checked_paths.size * 100 / total
        end

        def all_paths
          library_paths + signature_paths + code_paths
        end

        def checking_path?(path)
          [library_paths, signature_paths, code_paths].any? do |paths|
            paths.include?(path)
          end
        end

        def checked(path)
          raise unless checking_path?(path)
          checked_paths << path
        end

        def finished?
          total <= checked_paths.size
        end

        def unchecked_paths
          all_paths - checked_paths
        end

        def unchecked_code_paths
          code_paths - checked_paths
        end

        def unchecked_library_paths
          library_paths - checked_paths
        end

        def unchecked_signature_paths
          signature_paths - checked_paths
        end
      end

      attr_reader :project
      attr_reader :priority_paths
      attr_reader :changed_paths
      attr_reader :target_paths

      class TargetPaths
        attr_reader :project
        attr_reader :target
        attr_reader :code_paths
        attr_reader :signature_paths
        attr_reader :library_paths

        def initialize(project:, target:)
          @project = project
          @target = target
          @code_paths = Set[]
          @signature_paths = Set[]
          @library_paths = Set[]
        end

        def all_paths
          code_paths + signature_paths + library_paths
        end

        def library_path?(path)
          library_paths.include?(path)
        end

        def signature_path?(path)
          signature_paths.include?(path)
        end

        def code_path?(path)
          code_paths.include?(path)
        end

        def add(path, library: false)
          return true if signature_path?(path) || code_path?(path) || library_path?(path)

          if library
            library_paths << path
            true
          else
            relative_path = project.relative_path(path)

            case
            when target.source_pattern =~ relative_path
              code_paths << path
              true
            when target.signature_pattern =~ relative_path
              signature_paths << path
              true
            else
              false
            end
          end
        end

        alias << add
      end

      def initialize(project:)
        @project = project
        @priority_paths = Set[]
        @changed_paths = Set[]
        @target_paths = project.targets.each.map {|target| TargetPaths.new(project: project, target: target) }
      end

      def load(command_line_args:)
        loader = Services::FileLoader.new(base_dir: project.base_dir)

        files = {} #: Hash[String, String]

        target_paths.each do |paths|
          target = paths.target

          signature_service = Services::SignatureService.load_from(target.new_env_loader(project: project))
          paths.library_paths.merge(signature_service.env_rbs_paths)

          loader.each_path_in_patterns(target.source_pattern, command_line_args) do |path|
            paths.code_paths << project.absolute_path(path)
            files[path.to_s] = project.absolute_path(path).read
            if files.size > 1000
              yield files.dup
              files.clear
            end
          end
          loader.each_path_in_patterns(target.signature_pattern) do |path|
            paths.signature_paths << project.absolute_path(path)
            files[path.to_s] = project.absolute_path(path).read
            if files.size > 1000
              yield files.dup
              files.clear
            end
          end

          changed_paths.merge(paths.all_paths)
        end

        yield files.dup unless files.empty?
      end

      def push_changes(path)
        return if target_paths.any? {|paths| paths.library_path?(path) }

        target_paths.each {|paths| paths << path }

        if target_paths.any? {|paths| paths.code_path?(path) || paths.signature_path?(path) }
          changed_paths << path
        end
      end

      def update_priority(open: nil, close: nil)
        path = open || close
        path or raise

        target_paths.each {|paths| paths << path }

        case
        when open
          priority_paths << path
        when close
          priority_paths.delete path
        end
      end

      def make_request(guid: SecureRandom.uuid, last_request: nil, include_unchanged: false, progress:)
        return if changed_paths.empty? && !include_unchanged

        TypeCheckController::Request.new(guid: guid, progress: progress).tap do |request|
          if last_request
            request.library_paths.merge(last_request.unchecked_library_paths)
            request.signature_paths.merge(last_request.unchecked_signature_paths)
            request.code_paths.merge(last_request.unchecked_code_paths)
          end

          if include_unchanged
            target_paths.each do |paths|
              request.signature_paths.merge(paths.signature_paths)
              request.library_paths.merge(paths.library_paths)
              request.code_paths.merge(paths.code_paths)
            end
          else
            updated_paths = target_paths.select {|paths| changed_paths.intersect?(paths.all_paths) }

            updated_paths.each do |paths|
              case
              when paths.signature_paths.intersect?(changed_paths)
                request.signature_paths.merge(paths.signature_paths)
                request.library_paths.merge(paths.library_paths)
                request.code_paths.merge(paths.code_paths)
              when paths.code_paths.intersect?(changed_paths)
                request.code_paths.merge(paths.code_paths & changed_paths)
              end
            end
          end

          request.priority_paths.merge(priority_paths)

          changed_paths.clear()
        end
      end
    end
  end
end
