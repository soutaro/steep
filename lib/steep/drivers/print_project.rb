require "active_support/core_ext/hash/keys"

module Steep
  module Drivers
    class PrintProject
      attr_reader :stdout
      attr_reader :stderr

      attr_accessor :print_files
      attr_reader :files

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @print_files = false
      end

      def as_json(project)
        {
          steepfile: project.steepfile_path.to_s,
          targets: project.targets.map do |target|
            target_as_json(target)
          end
        }.stringify_keys
      end

      def target_as_json(target)
        json = {
          "name" => target.name.to_s,
          "source_pattern" => pattern_as_json(target.source_pattern),
          "signature_pattern" => pattern_as_json(target.signature_pattern),
          "groups" => target.groups.map do |group|
            group_as_json(group)
          end,
          "libraries" => target.new_env_loader().yield_self do |loader|
            libs = [] #: Array[library_json]
            loader.each_dir do |lib, path|
              case lib
              when :core
                libs << { "name" => "__core__", "path" => path.to_s }
              when Pathname
                raise "Unexpected pathname from loader: path=#{path}"
              else
                libs << { "name" => lib.name, "version" => lib.version, "path" => path.to_s }
              end
            end
            libs
          end,
          "unreferenced" => target.unreferenced
        } #: target_json

        if files
          files.each_group_signature_path(target, true) do |path|
            (json["signature_paths"] ||= []) << path.to_s
          end
          files.each_group_source_path(target, true) do |path|
            (json["source_paths"] ||= []) << path.to_s
          end
        end

        json
      end

      def group_as_json(group)
        json = {
          "name" => group.name.to_s,
          "source_pattern" => pattern_as_json(group.source_pattern),
          "signature_pattern" => pattern_as_json(group.signature_pattern)
        } #: group_json

        if files
          files.each_group_signature_path(group, true) do |path|
            (json["signature_paths"] ||= []) << path.to_s

          end
          files.each_group_source_path(group, true) do |path|
            (json["source_paths"] ||= []) << path.to_s
          end
        end

        json
      end

      def pattern_as_json(pattern)
        {
          "pattern" => pattern.patterns,
          "ignore" => pattern.ignores
        }
      end

      def run
        project = load_config()
        if print_files
          loader = Services::FileLoader.new(base_dir: project.base_dir)
          @files = files = Server::TargetGroupFiles.new(project)
          project.targets.each do |target|
            loader.each_path_in_target(target) do |path|
              files.add_path(path)
            end
          end
        else
          @files = nil
        end

        stdout.puts YAML.dump(as_json(project))

        0
      end
    end
  end
end
