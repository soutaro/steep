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

        def empty?
          total == 0
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

        def merge!(request)
          library_paths.merge(request.each_unchecked_library_target_path)
          signature_paths.merge(request.each_unchecked_signature_target_path)
          code_paths.merge(request.each_unchecked_code_target_path)

          self
        end
      end

      attr_reader :project
      attr_reader :priority_paths
      attr_reader :changed_paths
      attr_reader :files

      def initialize(project:)
        @project = project
        @priority_paths = Set[]
        @changed_paths = Set[]
        @files = TargetGroupFiles.new(project)
      end

      def load(command_line_args:)
        loader = Services::FileLoader.new(base_dir: project.base_dir)

        project.targets.each do |target|
          signature_service = Services::SignatureService.load_from(target.new_env_loader(), implicitly_returns_nil: target.implicitly_returns_nil)
          files.add_library_path(target, *signature_service.env_rbs_paths.to_a)
        end

        files = {} #: Hash[String, String]

        project.targets.each do |target|
          loader.each_path_in_target(target, command_line_args) do |path|
            path = project.absolute_path(path)
            self.files.add_path(path)
            files[project.relative_path(path).to_s] = path.read
            if files.size > 1000
              yield files.dup
              files.clear
            end
          end
        end

        changed_paths.merge(self.files.each_project_signature_path(nil))
        changed_paths.merge(self.files.each_project_source_path(nil))

        yield files.dup unless files.empty?
      end

      def push_changes(path)
        return if files.library_path?(path)

        if files.add_path(path)
          changed_paths << path
        end
      end

      def active_target?(target_group)
        priority_paths.any? do |path|
          if open_target = files.signature_paths.fetch(path, nil) || files.source_paths.fetch(path, nil)
            open_target == target_group
          end
        end
      end

      def push_changes_for_target(target_group)
        files.each_group_signature_path(target_group) do |path|
          push_changes path
        end

        files.each_group_source_path(target_group) do |path|
          push_changes path
        end
      end

      def update_priority(open: nil, close: nil)
        path = open || close or raise

        return if files.library_path?(path)
        files.add_path(path)

        case
        when open
          target_group = files.signature_paths.fetch(path, nil) || files.source_paths.fetch(path, nil) or return

          unless active_target?(target_group)
            push_changes_for_target(target_group)
          end
          priority_paths << path
        when close
          priority_paths.delete path
        end
      end

      def make_group_request(groups, progress:)
        TypeCheckController::Request.new(guid: progress.guid, progress: progress).tap do |request|
          if groups.empty?
            files.signature_paths.each do |path, target_group|
              target_group = target_group.target if target_group.is_a?(Project::Group)
              request.signature_paths << [target_group.name, path]
            end
            files.source_paths.each do |path, target_group|
              target_group = target_group.target if target_group.is_a?(Project::Group)
              request.code_paths << [target_group.name, path]
            end
          else
            group_set = groups.filter_map do |group_name|
              target_name, group_name = group_name.split(".", 2)
              target_name or raise

              target_name = target_name.to_sym
              group_name = group_name.to_sym if group_name

              if group_name
                if target = project.targets.find {|target| target.name == target_name }
                  target.groups.find {|group| group.name == group_name }
                end
              else
                project.targets.find {|target| target.name == target_name }
              end
            end.to_set

            files.signature_paths.each do |path, target_group|
              if group_set.include?(target_group)
                target_group = target_group.target if target_group.is_a?(Project::Group)
                request.signature_paths << [target_group.name, path]
              end
            end
            files.source_paths.each do |path, target_group|
              if group_set.include?(target_group)
                target_group = target_group.target if target_group.is_a?(Project::Group)
                request.code_paths << [target_group.name, path]
              end
            end
          end
        end
      end

      def make_request(guid: SecureRandom.uuid, include_unchanged: false, progress:)
        TypeCheckController::Request.new(guid: guid, progress: progress).tap do |request|
          if include_unchanged
            files.signature_paths.each do |path, target_group|
              target_group = target_group.target if target_group.is_a?(Project::Group)
              request.signature_paths << [target_group.name, path]
            end
            files.source_paths.each do |path, target_group|
              target_group = target_group.target if target_group.is_a?(Project::Group)
              request.code_paths << [target_group.name, path]
            end
          else
            changed_paths.each do |path|
              if target_group = files.signature_paths.fetch(path, nil)
                case target_group
                when Project::Group
                  target = target_group.target

                  files.each_group_signature_path(target_group) do |path|
                    request.signature_paths << [target.name, path]
                  end

                  files.each_group_source_path(target_group) do |path|
                    request.code_paths << [target.name, path]
                  end
                when Project::Target
                  files.each_target_signature_path(target_group, nil) do |path|
                    request.signature_paths << [target_group.name, path]
                  end

                  files.each_target_source_path(target_group, nil) do |path|
                    request.code_paths << [target_group.name, path]
                  end
                end
              end

              if target = files.source_path_target(path)
                request.code_paths << [target.name, path]
              end
            end

            unless request.signature_paths.empty?
              non_unref_targets = project.targets.reject { _1.unreferenced }.map(&:name).to_set
              if request.signature_paths.any? {|target_name, _| non_unref_targets.include?(target_name) }
                priority_paths.each do |path|
                  if target = files.signature_path_target(path)
                    request.signature_paths << [target.name, path]
                    request.priority_paths << path
                  end
                  if target = files.source_path_target(path)
                    request.code_paths << [target.name, path]
                    request.priority_paths << path
                  end
                end
              end
            end
          end

          changed_paths.clear()

          return nil if request.empty?
        end
      end
    end
  end
end
