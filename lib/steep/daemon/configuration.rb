# frozen_string_literal: true

module Steep
  module Daemon
    class Configuration
      attr_reader :socket_path, :pid_path, :log_path, :project_id, :socket_dir

      def initialize(base_dir: Dir.pwd)
        @socket_dir = File.join(Dir.tmpdir, "steep-server")
        @project_id = Digest::MD5.hexdigest(base_dir)[0, 8] #: String

        FileUtils.mkdir_p(@socket_dir)
        @socket_path = File.join(@socket_dir, "steep-#{@project_id}.sock")
        @pid_path = @socket_path.sub(".sock", ".pid")
        @log_path = @socket_path.sub(".sock", ".log")
      end
    end
  end
end
