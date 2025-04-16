module Steep
  module Server
    class TargetGroupFiles
      attr_reader :project

      attr_reader :source_paths, :signature_paths, :inline_paths

      attr_reader :library_paths

      def initialize(project)
        @project = project
        @source_paths = PathEnumerator.new()
        @signature_paths = PathEnumerator.new()
        @inline_paths = PathEnumerator.new()
        @library_paths = {}
        project.targets.each do |target|
          library_paths[target.name] = Set[]
        end
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
        if target_group = project.group_for_inline_path(path)
          inline_paths[path] = target_group
          return true
        end

        false
      end

      def add_library_path(target, *paths)
        library_paths.fetch(target.name).merge(paths)
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

      def path_target(path)
        signature_paths.target(path) || source_paths.target(path) || inline_paths.target(path)
      end

      def target_group_for_path(path)
        signature_paths.target_group(path) || source_paths.target_group(path) || inline_paths.target_group(path)
      end

      def [](path)
        signature_paths[path] || source_paths[path] || inline_paths[path]
      end

      def each_group_path(group, &block)
        if block
          signature_paths.each_group_path(group, &block)
          source_paths.each_group_path(group, &block)
          inline_paths.each_group_path(group, &block)
        else
          enum_for(_ = __method__, group)
        end
      end

      def each_target_path(target, except: nil, &block)
        if block
          signature_paths.each_target_path(target, except: except, &block)
          source_paths.each_target_path(target, except: except, &block)
          inline_paths.each_target_path(target, except: except, &block)
        else
          enum_for(_ = __method__, target, except: except)
        end
      end

      class PathEnumerator
        attr_reader :files

        def initialize()
          @files = {}
        end

        def []=(path, target_or_group)
          files[path] = target_or_group
        end

        def paths
          files.keys
        end

        def empty?
          files.empty?
        end

        def [](path)
          files.fetch(path, nil)
        end

        def each(&block)
          if block
            files.each do |path, group|
              target = target_of(group)
              group = group_of(group)
              yield [path, target, group]
            end
          else
            enum_for(_ = __method__)
          end
        end

        def target(path)
          if group = files.fetch(path, nil)
            target_of(group)
          end
        end

        def target_group(path)
          case target_or_group = files.fetch(path, nil)
          when Project::Target
            [target_or_group, nil]
          when Project::Group
            [target_or_group.target, target_or_group]
          end
        end

        def target_of(target_or_group)
          case target_or_group
          when Project::Group
            target_or_group.target
          when Project::Target
            target_or_group
          end
        end

        def group_of(target_or_group)
          case target_or_group
          when Project::Group
            target_or_group
          when Project::Target
            nil
          end
        end

        def each_project_path(except: nil, &block)
          if block
            files.each do |path, target|
              if except
                target = target_of(target)
                next if except == target
              end
              yield path
            end
          else
            enum_for(_ = __method__, except: except)
          end
        end

        def each_target_path(target, except: nil, &block)
          if block
            files.each do |path, path_group_target|
              if path_group_target.is_a?(Project::Group)
                path_target = path_group_target.target
                path_group = path_group_target
              else
                path_target = path_group_target
                path_group = Object.new  # A dummy value that cannot be equal to any possible `except:` value
              end

              next unless target == path_target
              next if except == path_group

              yield path
            end
          else
            enum_for(_ = __method__, target, except: except)
          end
        end

        def each_group_path(group, &block)
          if block
            files.each do |path, path_group_target|
              next unless group == path_group_target
              yield path
            end
          else
            enum_for(_ = __method__, group)
          end
        end
      end
    end
  end
end
