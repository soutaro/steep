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
        attr_reader :report_progress

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
          @report_progress = false
        end

        def report_progress!(value = true)
          @report_progress = value
          self
        end

        def uri(path)
          Steep::PathHelper.to_uri(path)
        end

        def as_json(assignment:)
          {
            guid: guid,
            library_uris: assigned_uris(assignment, library_paths),
            signature_uris: assigned_uris(assignment, signature_paths),
            code_uris: assigned_uris(assignment, code_paths),
            priority_uris: priority_paths.map {|path| uri(path).to_s }
          }
        end

        def assigned_uris(assignment, paths)
          paths.filter_map do |target_path|
            if assignment =~ target_path
              [target_path[0].to_s, uri(target_path[1]).to_s]
            end
          end
        end

        def total
          library_paths.size + signature_paths.size + code_paths.size
        end

        def percentage
          checked_paths.size * 100 / total
        end

        def each_path(&block)
          if block
            each_target_path do |_target, path|
              yield path
            end
          else
            enum_for :each_path
          end
        end

        def each_target_path(&block)
          if block
            library_paths.each(&block)
            signature_paths.each(&block)
            code_paths.each(&block)
          else
            enum_for :each_target_path
          end
        end

        def checking_path?(target_path)
          [library_paths, signature_paths, code_paths].any? do |paths|
            paths.include?(target_path)
          end
        end

        def checked(path, target)
          target_path = [target.name, path] #: target_and_path

          raise unless checking_path?(target_path)
          checked_paths << target_path
        end

        def finished?
          total <= checked_paths.size
        end

        def each_unchecked_path(&block)
          if block
            each_unchecked_target_path do |_target, path|
              yield path
            end
          else
            enum_for :each_unchecked_path
          end
        end

        def each_unchecked_target_path(&block)
          if block
            each_target_path do |target_path|
              unless checked_paths.include?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_target_path
          end
        end

        def each_unchecked_code_target_path(&block)
          if block
            code_paths.each do |target_path|
              unless checked_paths.include?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_code_target_path
          end
        end

        def each_unchecked_library_target_path(&block)
          if block
            library_paths.each do |target_path|
              unless checked_paths.include?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_library_target_path
          end
        end

        def each_unchecked_signature_target_path(&block)
          if block
            signature_paths.each do |target_path|
              unless checked_paths.include?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_signature_target_path
          end
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

        def signature_path_changed?(changed_paths)
          signature_paths.intersect?(changed_paths)
        end

        def code_path_changed?(changed_paths)
          if code_paths.intersect?(changed_paths)
            code_paths & changed_paths
          end
        end
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
          if include_unchanged
            target_paths.each do |paths|
              request.signature_paths.merge(paths.signature_paths.map { [paths.target.name, _1] })
              request.library_paths.merge(paths.library_paths.map { [paths.target.name, _1] })
              request.code_paths.merge(paths.code_paths.map { [paths.target.name, _1] })
            end
          else
            if last_request
              request.library_paths.merge(last_request.each_unchecked_library_target_path)
              request.signature_paths.merge(last_request.each_unchecked_signature_target_path)
              request.code_paths.merge(last_request.each_unchecked_code_target_path)
            end

            target_paths.each do |paths|
              case
              when paths.signature_path_changed?(changed_paths)
                paths.signature_paths.each { request.signature_paths << [paths.target.name, _1] }
                paths.library_paths.each { request.library_paths << [paths.target.name, _1] }
                paths.code_paths.each { request.code_paths << [paths.target.name, _1] }
              when code_paths = paths.code_path_changed?(changed_paths)
                code_paths.each do
                  request.code_paths << [paths.target.name, _1]
                end
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
