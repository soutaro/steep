# frozen_string_literal: true

require "tmpdir"

require "steep/daemon/configuration"
require "steep/daemon/server"

module Steep
  module Daemon
    SOCKET_DIR = File.join(Dir.tmpdir, "steep-server")

    LARGE_LOG_FILE_THRESHOLD = 10 * 1024 * 1024

    class << self
      def config
        @config ||= Configuration.new
      end

      def project_id
        config.project_id
      end

      def socket_path
        config.socket_path
      end

      def pid_path
        config.pid_path
      end

      def log_path
        config.log_path
      end

      def starting?
        return false unless File.exist?(pid_path)
        return false if File.exist?(socket_path)

        pid = File.read(pid_path).to_i
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::ENOENT
        false
      end

      def running?
        return false unless File.exist?(pid_path) && File.exist?(socket_path)

        pid = File.read(pid_path).to_i
        Process.kill(0, pid)
        socket = UNIXSocket.new(socket_path)
        socket.close
        true
      rescue Errno::ESRCH, Errno::ENOENT, Errno::ECONNREFUSED, Errno::ENOTSOCK
        false
      end

      def cleanup
        [socket_path, pid_path].each do |path|
          File.delete(path)
        rescue Errno::ENOENT
          # File already deleted
        end
      end

      def start(stderr:)
        if running?
          stderr.puts "Steep server already running (PID: #{File.read(pid_path).strip})"
          return true
        end

        cleanup

        unless Process.respond_to?(:fork)
          stderr.puts "fork() not available, cannot start steep server daemon"
          return false
        end

        child_pid = fork do
          Process.setsid
          daemon_pid = fork do
            File.write(pid_path, Process.pid.to_s)
            log_file = File.open(log_path, "a")
            log_file.sync = true
            $stdout.reopen(log_file)
            $stderr.reopen(log_file)
            $stdin.reopen("/dev/null")
            run_server(stderr:)
          end
          exit!(0) if daemon_pid
        end

        Process.waitpid(child_pid) if child_pid

        40.times do
          sleep 0.5
          next unless running?

          stderr.puts "Steep server started (PID: #{File.read(pid_path).strip})"
          return true
        end

        stderr.puts "Failed to start steep server. Check log: #{log_path}"
        false
      end

      def stop(stderr:)
        unless File.exist?(pid_path)
          stderr.puts "Steep server is not running"
          return
        end

        pid = File.read(pid_path).to_i
        Process.kill("TERM", pid)
        process_alive = true
        20.times do
          sleep 0.5
          Process.kill(0, pid)
        rescue Errno::ESRCH
          process_alive = false
          break
        end

        if process_alive
          Process.kill("KILL", pid)
          stderr.puts "Steep server did not stop gracefully, forcefully killed (PID: #{pid})"
        else
          stderr.puts "Steep server stopped (PID: #{pid})"
        end
        cleanup
      rescue Errno::ESRCH
        cleanup
        stderr.puts "Steep server was not running (cleaned up stale files)"
      end

      def status(stderr:)
        if running?
          pid = File.read(pid_path).to_i
          stderr.puts "Steep server running (PID: #{pid})"
          stderr.puts "  Socket: #{socket_path}"
          stderr.puts "  Log:    #{log_path}"

          if File.exist?(log_path)
            log_content = if File.size(log_path) > LARGE_LOG_FILE_THRESHOLD
                            # SAFE: log_path is controlled internally, no user input
                            `tail -n 20 #{log_path.shellescape}`
                          else
                            File.readlines(log_path).last(20).join
                          end

            if log_content.include?("Warm-up complete")
              stderr.puts "  Status: Ready"
            elsif log_content.include?("Warming up type checker")
              stderr.puts "  Status: Warming up (loading RBS environment)"
            else
              stderr.puts "  Status: Starting"
            end
          end
        else
          stderr.puts "Steep server is not running"

          if File.exist?(pid_path) || File.exist?(socket_path)
            stderr.puts "  (Found stale files - run 'steep server stop' to clean up)"
          end
        end
      end

      private

      def run_server(stderr:)
        project = load_project
        server = Server.new(config: config, project: project, stderr:)
        server.run
      end

      def load_project
        steep_file = Pathname("Steepfile")
        steep_file_path = steep_file.realpath

        project = ::Steep::Project.new(steepfile_path: steep_file_path)
        ::Steep::Project::DSL.parse(project, steep_file.read, filename: steep_file.to_s)

        project.targets.each do |target|
          case target.options.load_collection_lock
          when nil, RBS::Collection::Config::Lockfile
            # OK
          when RBS::Collection::Config::CollectionNotAvailable
            config_path = target.options.collection_config_path || raise
            lockfile_path = RBS::Collection::Config.to_lockfile_path(config_path)
            RBS::Collection::Installer.new(
              lockfile_path: lockfile_path, stdout: $stderr
            ).install_from_lockfile
            target.options.load_collection_lock(force: true)
          end
        end

        project
      end
    end
  end
end
