module Steep
  module Server
    class TargetGroupFiles
      class PathEnumerator
        def initialize
          @paths = {}
        end

        def empty?
          @paths.empty?
        end

        def paths
          @paths.keys
        end

        def registered_path?(path)
          @paths.key?(path)
        end

        def []=(path, target_group)
          @paths[path] = target_group
        end

        def [](path)
          @paths[path]
        end

        def each(&block)
          if block
            @paths.each do |path, target_group|
              target = target_of(target_group)
              group = group_of(target_group)

              yield [path, target, group]
            end
          else
            enum_for(_ = __method__)
          end
        end

        def target(path)
          if target_group = @paths.fetch(path, nil)
            target_of(target_group)
          end
        end

        def target_group(path)
          if target_group = @paths.fetch(path, nil)
            target = target_of(target_group)
            group = group_of(target_group)

            [target, group]
          end
        end

        def each_project_path(except: nil, &block)
          if block
            @paths.each_key do |path|
              target, group = target_group(path) || raise

              next if target == except

              yield [path, target, group, group || target]
            end
          else
            enum_for(_ = __method__, except: except)
          end
        end

        def each_target_path(target, except: nil, &block)
          if block
            @paths.each_key do |path|
              t, g = target_group(path) || raise

              if except
                next if g == except
              end

              next unless t == target

              yield [path, t, g, g || t]
            end
          else
            enum_for(_ = __method__, target, except: except)
          end
        end

        def each_group_path(target_group, include_sub_groups: false, &block)
          if block
            if include_sub_groups
              target_group.is_a?(Project::Target) or raise "target_group must be a target if `include_sub_groups:` is given. (#{target_group.name})"
              each_target_path(target_group, &block)
            else
              @paths.each do |path, tg|
                if tg == target_group
                  t, g = target_group(path) || raise
                  yield [path, t, g, g || t]
                end
              end
            end
          else
            enum_for(_ = __method__, target_group, include_sub_groups: include_sub_groups)
          end
        end

        def target_of(target_group)
          case target_group
          when Project::Target
            target_group
          when Project::Group
            target_group.target
          end
        end

        def group_of(target_group)
          case target_group
          when Project::Group
            target_group
          end
        end
      end

      attr_reader :project

      attr_reader :source_paths, :signature_paths, :inline_paths

      attr_reader :library_paths

      def initialize(project)
        @project = project
        @source_paths = PathEnumerator.new
        @signature_paths = PathEnumerator.new
        @inline_paths = PathEnumerator.new
        @library_paths = {}
      end

      def add_path(path)
        if target_group = project.group_for_signature_path(path)
          signature_paths[path] = target_group
          return true
        end
        if target_group = project.group_for_inline_source_path(path)
          inline_paths[path] = target_group
          return true
        end
        if target_group = project.group_for_source_path(path)
          source_paths[path] = target_group
          return true
        end

        false
      end

      def registered_path?(path)
        source_paths.registered_path?(path) ||
          signature_paths.registered_path?(path) ||
          inline_paths.registered_path?(path)
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
    end
  end
end
