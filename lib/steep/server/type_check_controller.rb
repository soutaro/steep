module Steep
  module Server
    class TypeCheckController
      class Request
        attr_reader :guid
        attr_reader :library_paths
        attr_reader :code_paths, :inline_paths, :signature_paths
        attr_reader :priority_paths
        attr_reader :checked_paths
        attr_reader :work_done_progress
        attr_reader :started_at
        attr_accessor :needs_response
        attr_reader :report_progress

        def initialize(guid:, targets:, progress:)
          @guid = guid
          @library_paths = {}
          targets.each do |target|
            library_paths[target.name] = Set[]
          end
          @code_paths = Set[]
          @inline_paths = Set[]
          @signature_paths = Set[]
          @priority_paths = Set[]
          @checked_paths = Set[]
          @work_done_progress = progress
          @started_at = Time.now
          @needs_response = false
          @report_progress = false
        end

        def add_library_path(target, path)
          library_paths.fetch(target.name) << path
        end

        def add_project_path(target, path)
          relative_path = target.project.relative_path(path)
          if target.source_file_path?(relative_path)
            add_code_path(target, path)
          end
          if target.signature_file_path?(relative_path)
            add_signature_path(target, path)
          end
          if target.inline_source_file_path?(relative_path)
            add_inline_path(target, path)
          end
        end

        def add_code_path(target, path)
          code_paths << [target.name, path]
        end

        def add_signature_path(target, path)
          signature_paths << [target.name, path]
        end

        def add_inline_path(target, path)
          inline_paths << [target.name, path]
        end

        def report_progress!(value = true)
          @report_progress = value
          self
        end

        def uri(path)
          Steep::PathHelper.to_uri(path)
        end

        def as_json(assignment:)
          library_uris = {} #: Hash[String, Array[String]]
          library_paths.each do |target, paths|
            library_uris[target.name.to_s] = assigned_uris(assignment, target, paths)
          end

          {
            guid: guid,
            library_uris: library_uris,
            code_uris: code_paths.map {|target, path| [target.to_s, uri(path).to_s] },
            inline_uris: inline_paths.map {|target, path| [target.to_s, uri(path).to_s] },
            signature_uris: signature_paths.map {|target, path| [target.to_s, uri(path).to_s] },
            priority_uris: priority_paths.map {|path| uri(path).to_s }
          }
        end

        def assigned_uris(assignment, target, paths)
          paths.filter_map do |path|
            if assignment =~ [target, path]
              uri(path).to_s
            end
          end
        end

        def total
          library_paths.each_value.sum(&:size) + code_paths.size + inline_paths.size + signature_paths.size
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

        def project_target_path(target_path)
          code_paths.include?(target_path) ||
            signature_paths.include?(target_path) ||
            inline_paths.include?(target_path)
        end

        def library_target_path(target_path)
          target, path = target_path
          library_paths.fetch(target).include?(path)
        end

        def each_target_path(&block)
          if block
            library_paths.each do |target, paths|
              paths.each do |path|
                yield [target, path]
              end
            end
            code_paths.each(&block)
            inline_paths.each(&block)
            signature_paths.each(&block)
          else
            enum_for :each_target_path
          end
        end

        def checking_path?(target_path)
          target, path = target_path

          library_paths.fetch(target, Set[]).include?(path) ||
            code_paths.include?(target_path) ||
            signature_paths.include?(target_path) ||
            inline_paths.include?(target_path)
        end

        def type_checked?(target_path)
          raise unless checking_path?(target_path)
          checked_paths.include?(target_path)
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
              unless type_checked?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_target_path
          end
        end

        def each_unchecked_project_target_path(&block)
          if block
            each_unchecked_target_path do |target_path|
              if project_target_path?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_code_target_path
          end
        end

        def each_unchecked_library_target_path(&block)
          if block
            each_unchecked_target_path do |target_path|
              if library_target_path?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_library_target_path
          end
        end

        def merge!(request)
          library_paths.merge!(request.library_paths) do |target, self_paths, other_paths|
            self_paths + other_paths
          end
          code_paths.merge(request.code_paths)
          inline_paths.merge(request.inline_paths)
          signature_paths.merge(request.signature_paths)

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

        changed_paths.merge(self.files.signature_paths.each_project_path)
        changed_paths.merge(self.files.source_paths.each_project_path)
        changed_paths.merge(self.files.inline_paths.each_project_path)

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
          if open_target = files[path]
            open_target == target_group
          end
        end
      end

      def push_changes_for_target(target_group)
        files.signature_paths.each_group_path(target_group) do |path|
          push_changes path
        end
        files.source_paths.each_group_path(target_group) do |path|
          push_changes path
        end
        files.inline_paths.each_group_path(target_group) do |path|
          push_changes path
        end
      end

      def update_priority(open: nil, close: nil)
        path = open || close or raise

        return if files.library_path?(path)
        files.add_path(path)

        case
        when open
          target_group = files[path] or return

          unless active_target?(target_group)
            push_changes_for_target(target_group)
          end
          priority_paths << path
        when close
          priority_paths.delete path
        end
      end

      def make_group_request(groups, progress:)
        TypeCheckController::Request.new(guid: progress.guid, targets: project.targets, progress: progress).tap do |request|
          if groups.empty?
            files.signature_paths.each do |path, target, _group|
              request.add_signature_path(target, path)
            end
            files.source_paths.each do |path, target, _group|
              request.add_code_path(target, path)
            end
            files.inline_paths.each do |path, target, _group|
              request.add_inline_path(target, path)
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

            files.signature_paths.each do |path, target|
              if group_set.include?(target)
                request.add_signature_path(target, path)
              end
            end
            files.source_paths.each do |path, target|
              if group_set.include?(target)
                request.add_code_path(target, path)
              end
            end
            files.inline_paths.each do |path, target|
              if group_set.include?(target)
                request.add_inline_path(target, path)
              end
            end
          end
        end
      end

      def make_request(guid: SecureRandom.uuid, include_unchanged: false, progress:)
        Steep.logger.tagged "make_request(guid: #{guid}, include_unchanged: #{include_unchanged}, progress: #{progress.class})" do
          TypeCheckController::Request.new(guid: guid, targets: project.targets, progress: progress).tap do |request|
            if include_unchanged
              files.signature_paths.each do |path, target|
                request.add_signature_path(target, path)
              end
              files.source_paths.each do |path, target|
                request.add_code_path(target, path)
              end
              files.inline_paths.each do |path, target|
                request.add_inline_path(target, path)
              end
            else
              signature_updated_targets = Set[] #: Set[Symbol]

              changed_paths.each do |path|
                if (target, group = files.signature_paths.target_group(path))
                  if group
                    unless target.unreferenced
                      signature_updated_targets << target.name
                    end
                    files.each_group_path(group) do |path|
                      request.add_project_path(target, path)
                    end
                  else
                    unless target.unreferenced
                      signature_updated_targets << target.name
                    end

                    files.each_target_path(target) do |path|
                      request.add_project_path(target, path)
                    end
                  end
                end

                if (target, group = files.inline_paths.target_group(path))
                  if group
                    unless target.unreferenced
                      signature_updated_targets << target.name
                    end
                    files.each_group_path(group) do |path|
                      request.add_project_path(target, path)
                    end
                  else
                    unless target.unreferenced
                      signature_updated_targets << target.name
                    end

                    files.each_target_path(target) do |path|
                      request.add_project_path(target, path)
                    end
                  end
                end

                if target = files.source_paths.target(path)
                  request.add_code_path(target, path)
                end
              end

              unless signature_updated_targets.empty?
                priority_paths.each do |path|
                  if target = files.signature_paths.target(path)
                    request.add_signature_path(target, path)
                    request.priority_paths << path
                  end
                  if target = files.source_paths.target(path)
                    request.add_code_path(target, path)
                    request.priority_paths << path
                  end
                  if target = files.inline_paths.target(path)
                    request.add_inline_path(target, path)
                    request.priority_paths << path
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
end
