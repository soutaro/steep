module Steep
  module Drivers
    module Utils
      module DriverHelper
        attr_accessor :steepfile

        def load_config(path: steepfile || Pathname("Steepfile"))
          raise "Cannot find a configuration at #{path}: `steep init` to scaffold" unless path.file?

          steep_file_path = path.absolute? ? path : Pathname.pwd + path
          Project.new(steepfile_path: steep_file_path).tap do |project|
            Project::DSL.parse(project, path.read, filename: path.to_s)
          end
        end

        def type_check(project)
          project.targets.each do |target|
            Steep.logger.tagged "target=#{target.name}" do
              target.type_check
            end
          end
        end
      end
    end
  end
end
