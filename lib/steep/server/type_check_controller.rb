module Steep
  module Server
    class TypeCheckController
      class Request
        attr_reader :guid
        attr_reader :library_paths
        attr_reader :signature_paths
        attr_reader :code_paths
        attr_reader :inline_paths
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
          @inline_paths = Set[]
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
            inline_uris: assigned_uris(assignment, inline_paths),
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
          library_paths.size + signature_paths.size + code_paths.size + inline_paths.size
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
            inline_paths.each(&block)
          else
            enum_for :each_target_path
          end
        end

        def checking_path?(target_path)
          [library_paths, signature_paths, code_paths, inline_paths].any? do |paths|
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

        def each_unchecked_inline_target_path(&block)
          if block
            inline_paths.each do |target_path|
              unless checked_paths.include?(target_path)
                yield target_path
              end
            end
          else
            enum_for :each_unchecked_inline_target_path
          end
        end

        def merge!(request)
          library_paths.merge(request.each_unchecked_library_target_path)
          signature_paths.merge(request.each_unchecked_signature_target_path)
          code_paths.merge(request.each_unchecked_code_target_path)
          inline_paths.merge(request.each_unchecked_inline_target_path)

          self
        end
      end

      attr_reader :project
      attr_reader :open_paths
      attr_reader :active_groups
      attr_reader :new_active_groups
      attr_reader :dirty_code_paths, :dirty_signature_paths, :dirty_inline_paths
      attr_reader :files
      attr_reader :inline_path_changes

      def initialize(project:)
        @project = project

        @files = TargetGroupFiles.new(project)
        @open_paths = Set[]
        @active_groups = Set[].compare_by_identity
        @new_active_groups = Set[].compare_by_identity
        @dirty_code_paths = Set[]
        @dirty_signature_paths = Set[]
        @dirty_inline_paths = Set[]
        @inline_path_changes = InlineSourceChangeDetector.new
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
            absolute_path = project.absolute_path(path)
            self.files.add_path(absolute_path)
            content = absolute_path.read
            files[path.to_s] = content
            if files.size > 1000
              yield files.dup
              files.clear
            end

            if inline_path?(path)
              inline_path_changes.add_source(path, content)
            end
          end
        end

        yield files.dup unless files.empty?
      end

      def code_path?(path)
        files.source_paths.registered_path?(path) || project.target_for_source_path(path) != nil
      end

      def signature_path?(path)
        files.signature_paths.registered_path?(path) || project.target_for_signature_path(path) != nil
      end

      def inline_path?(path)
        Steep.logger.fatal { {
          path: path,
          inline: files.inline_paths.paths.map(&:to_s),
          target: project.target_for_inline_source_path(path)&.name
        }.inspect }
        files.inline_paths.registered_path?(path) || project.target_for_inline_source_path(path) != nil
      end

      def add_dirty_code_path(path)
        return if files.library_path?(path)
        if code_path?(path)
          files.add_path(path)
          dirty_code_paths << path
        end
      end

      def add_dirty_signature_path(path)
        return if files.library_path?(path)
        if signature_path?(path)
          files.add_path(path)
          dirty_signature_paths << path
        end
      end

      def add_dirty_inline_path(path, update)
        return if files.library_path?(path)
        if inline_path?(path)
          files.add_path(path)
          dirty_inline_paths << path

          unless inline_path_changes.has_source?(path)
            inline_path_changes.add_source(path, "")
          end

          if update.is_a?(String)
            inline_path_changes.replace_source(path, update)
          else
            inline_path_changes.accumulate_change(path, update)
          end
        end
      end

      def open_inline_path(path, content)
        return if files.library_path?(path)

        if inline_path?(path)
          open_path(path)

          if inline_path_changes.has_source?(path)
            inline_path_changes.replace_source(path, content)
          else
            inline_path_changes.add_source(path, content)
          end
        end
      end

      def each_dirty_path(&block)
        if block
          dirty_code_paths.each(&block)
          dirty_signature_paths.each(&block)
          dirty_inline_paths.each(&block)
        else
          enum_for(:each_dirty_path)
        end
      end

      def active_group?(group)
        active_groups.include?(group)
      end

      def each_active_group(&block)
        if block
          active_groups.each(&block)
        else
          enum_for(_ = __method__)
        end
      end

      def unreferenced?(group)
        group = group.target if group.is_a?(Project::Group)
        group.unreferenced
      end

      def reset()
        dirty_code_paths.clear()
        dirty_signature_paths.clear()
        dirty_inline_paths.clear()
        new_active_groups.clear()
        inline_path_changes.reset
      end

      def open_path(path)
        return if open_paths.include?(path)

        files.add_path(path) or return

        if group = group_of(path)
          open_paths << path

          unless active_groups.include?(group)
            new_active_groups << group
            active_groups << group
          end
        end
      end

      def close_path(path)
        if open_paths.include?(path)
          closed_path_group = group_of(path) or raise

          open_paths.delete(path)

          if open_paths.none? { group_of(_1) == closed_path_group }
            active_groups.delete(closed_path_group)
            new_active_groups.delete(closed_path_group)
          end
        end
      end

      def group_of(path)
        files.signature_paths[path] ||
          files.source_paths[path] ||
          files.inline_paths[path]
      end

      def target_of(path)
        if group = group_of(path)
          if group.is_a?(Project::Group)
            group.target
          else
            group
          end
        end
      end

      def make_group_request(groups, guid: SecureRandom.uuid, progress:)
        TypeCheckController::Request.new(guid: progress.guid, progress: progress).tap do |request|
          raise "At least one group/target must be specified" if groups.empty?

          name_group_map = {} #: Hash[String, group]

          project.targets.each do |target|
            name_group_map[target.name.to_s] = target

            target.groups.each do |group|
              name_group_map["#{target.name}.#{group.name}"] = group
            end
          end

          groups.each do |group|
            type_check_group = name_group_map.fetch(group)

            new_active_groups.delete(type_check_group)

            files.signature_paths.each_group_path(type_check_group) do |path, target|
              request.signature_paths << [target.name, path]
              dirty_signature_paths.delete(path)
            end
            files.inline_paths.each_group_path(type_check_group) do |path, target|
              request.inline_paths << [target.name, path]
              dirty_inline_paths.delete(path)
            end
            files.source_paths.each_group_path(type_check_group) do |path, target|
              request.code_paths << [target.name, path]
              dirty_code_paths.delete(path)
            end
          end

          request.priority_paths.merge(open_paths)
        end
      end

      def make_all_request(guid: SecureRandom.uuid, progress:)
        TypeCheckController::Request.new(guid: guid, progress: progress).tap do |request|
          files.signature_paths.each do |path, target|
            request.signature_paths << [target.name, path]
          end
          files.source_paths.each do |path, target|
            request.code_paths << [target.name, path]
          end
          files.inline_paths.each do |path, target|
            request.inline_paths << [target.name, path]
          end

          request.priority_paths.merge(open_paths)

          reset()
        end
      end

      def make_request(guid: SecureRandom.uuid, progress:)
        TypeCheckController::Request.new(guid: guid, progress: progress).tap do |request|
          code_paths = Set[] #: Set[[group, Pathname]]
          signature_paths = Set[] #: Set[[group, Pathname]]
          inline_paths = Set[] #: Set[[group, Pathname]]

          dirty_code_paths.each do |path|
            group = files.source_paths[path] or raise "#{path} is not a code path"
            code_paths << [group, path]
          end

          dirty_signature_paths.each do |path|
            group = files.signature_paths[path] or raise "#{path} is not a signature path"
            signature_paths << [group, path]
          end

          dirty_inline_paths.each do |path|
            group = files.inline_paths[path] or raise "#{path} is not an inline path"
            inline_paths << [group, path]
          end

          signature_updated_groups = Set[] #: Set[group]

          signature_paths.each do |group, path|
            signature_updated_groups << group
          end

          updated_inline_paths = inline_path_changes.type_updated_paths(dirty_inline_paths)
          inline_paths.each do |group, path|
            if updated_inline_paths.include?(path)
              signature_updated_groups << group
            end
          end

          type_check_groups = Set[] #: Set[group]

          type_check_groups.merge(signature_updated_groups)

          unless signature_updated_groups.all? { unreferenced?(_1) }
            type_check_groups.merge(active_groups)
          end

          type_check_groups.merge(new_active_groups)

          type_check_groups.each do |group|
            files.signature_paths.each_group_path(group) do |path, target|
              signature_paths << [target, path]
            end
            files.inline_paths.each_group_path(group) do |path, target|
              inline_paths << [target, path]
            end
            files.source_paths.each_group_path(group) do |path, target|
              code_paths << [target, path]
            end
          end

          signature_paths.each do |_, path|
            target = target_of(path) or raise
            request.signature_paths << [target.name, path]
          end

          inline_paths.each do |_, path|
            target = target_of(path) or raise
            request.inline_paths << [target.name, path]
          end

          code_paths.each do |_, path|
            target = target_of(path) or raise
            request.code_paths << [target.name, path]
          end

          request.priority_paths.merge(open_paths)

          reset()

          return nil if request.empty?
        end
      end
    end
  end
end
