module Steep
  module Server
    class TargetGroupFiles
      attr_reader :project

      attr_reader :source_paths, :signature_paths

      attr_reader :library_paths

      def initialize(project)
        @project = project
        @source_paths = {}
        @signature_paths = {}
        @library_paths = {}
      end

      def add_path(path)
        if target_group = project.group_for_signature_path(path)
          signature_paths[path] = target_group
          return true
        end
        if target_group = project.group_for_source_path(path)
          source_paths[path] = target_group
          return true
        end

        false
      end

      def add_library_path(target, *paths)
        (library_paths[target.name] ||= Set[]).merge(paths)
      end

      def each_library_path(target, &block)
        if block
          library_paths.fetch(target.name).each(&block)
        else
          enum_for(_ = __method__, target)
        end
      end

      def library_path?(path)
        library_paths.each_value.any? { _1.include?(path) }
      end

      def signature_path_target(path)
        case target_group = signature_paths.fetch(path, nil)
        when Project::Target
          target_group
        when Project::Group
          target_group.target
        end
      end

      def source_path_target(path)
        case target_group = source_paths.fetch(path, nil)
        when Project::Target
          target_group
        when Project::Group
          target_group.target
        end
      end

      def target_group_for_source_path(path)
        ret = source_paths.fetch(path, nil)
        case ret
        when Project::Group
          [ret.target, ret]
        when Project::Target
          [ret, nil]
        end
      end

      def target_group_for_signature_path(path)
        ret = signature_paths.fetch(path, nil)
        case ret
        when Project::Group
          [ret.target, ret]
        when Project::Target
          [ret, nil]
        end
      end

      def each_group_signature_path(target, no_group = false, &block)
        if block
          signature_paths.each_key do |path|
            t, g = target_group_for_signature_path(path)

            if target.is_a?(Project::Target)
              if no_group
                yield path if t == target && g == nil
              else
                yield path if t == target
              end
            else
              yield path if g == target
            end
          end
        else
          enum_for(_ = __method__, target, no_group)
        end
      end

      def each_target_signature_path(target, group, &block)
        raise unless group.target == target if group

        if block
          signature_paths.each_key do |path|
            t, g = target_group_for_signature_path(path)

            next unless target == t
            next if group && group == g

            yield path
          end
        else
          enum_for(_ = __method__, target, group)
        end
      end

      def each_project_signature_path(target, &block)
        if block
          signature_paths.each do |path, target_group|
            t =
              case target_group
              when Project::Target
                target_group
              when Project::Group
                target_group.target
              end

            if target
              next if t.unreferenced
              next if t == target
            end

            yield path
          end
        else
          enum_for(_ = __method__, target)
        end
      end

      def each_group_source_path(target, no_group = false, &block)
        if block
          source_paths.each_key do |path|
            t, g = target_group_for_source_path(path)

            if target.is_a?(Project::Target)
              if no_group
                yield path if t == target && g == nil
              else
                yield path if t == target
              end
            else
              yield path if g == target
            end
          end
        else
          enum_for(_ = __method__, target, no_group)
        end
      end

      def each_target_source_path(target, group, &block)
        raise unless group.target == target if group

        if block
          source_paths.each_key do |path|
            t, g = target_group_for_source_path(path)

            next unless target == t
            next if group && group == g

            yield path
          end
        else
          enum_for(_ = __method__, target, group)
        end
      end

      def each_project_source_path(target, &block)
        if block
          source_paths.each do |path, target_group|
            t =
              case target_group
              when Project::Target
                target_group
              when Project::Group
                target_group.target
              end

            if target
              next if t.unreferenced
              next if t == target
            end

            yield path
          end
        else
          enum_for(_ = __method__, target)
        end
      end
    end
  end
end
