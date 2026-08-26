# frozen_string_literal: true

module Steep
  module Server
    # Accepts connections on a UNIX socket and forwards the received requests to the master
    #
    # Started by `steep langserver` so that CLI commands like `steep query` and `steep check` can
    # talk to the language server the IDE is running, instead of a standalone daemon process.
    #
    class CommandSocket
      LSP = LanguageServer::Protocol

      # A connection from a CLI client
      #
      # `#write` never raises even if the client is disconnected, because it may be called from
      # the master's write thread, which should keep running for other clients.
      #
      class Session
        attr_reader :socket

        def initialize(socket)
          @socket = socket
          @writer = LSP::Transport::Io::Writer.new(socket)
          @mutex = Mutex.new
          @closed = false
        end

        def write(message)
          @mutex.synchronize do
            return if @closed
            @writer.write(message)
          end
        rescue SystemCallError, IOError
          close()
        end

        def close
          @mutex.synchronize do
            @closed = true
          end
          begin
            @socket.close
          rescue IOError
            # Already closed
          end
        end
      end

      attr_reader :master, :configuration

      def initialize(master:, configuration:)
        @master = master
        @configuration = configuration
        @server = nil
        @accept_thread = nil
      end

      def socket_path
        configuration.socket_path
      end

      # Binds the UNIX socket and starts accepting connections in a background thread
      #
      # Returns `false` without binding when another process (a standalone `steep server` daemon or
      # another language server) is already serving on the socket.
      #
      def start
        if File.exist?(socket_path)
          if socket_alive?
            Steep.logger.warn { "Command socket is already served by another process: #{socket_path}" }
            return false
          end

          unless File.socket?(socket_path)
            Steep.logger.error { "#{socket_path} exists but is not a socket, skipping command socket setup" }
            return false
          end

          File.delete(socket_path)
        end

        @server = UNIXServer.new(socket_path)
        File.chmod(0o600, socket_path)

        @accept_thread = Thread.new do
          Thread.current.abort_on_exception = false
          accept_loop()
        end

        Steep.logger.info { "Command socket is ready: #{socket_path}" }

        true
      rescue Errno::EADDRINUSE
        Steep.logger.warn { "Command socket is already served by another process: #{socket_path}" }
        false
      end

      def stop
        server = @server
        @server = nil

        if server
          begin
            server.close
          rescue IOError
            # Already closed
          end

          @accept_thread&.join(1)

          begin
            File.delete(socket_path)
          rescue Errno::ENOENT
            # Already deleted
          end
        end
      end

      private

      def socket_alive?
        socket = UNIXSocket.new(socket_path)
        socket.close
        true
      rescue SystemCallError
        false
      end

      def accept_loop
        while server = @server
          socket =
            begin
              server.accept
            rescue IOError, SystemCallError => error
              Steep.logger.info { "Command socket accept loop stopping: #{error.inspect}" }
              break
            end

          # The loop must survive anything but the accept errors above: it runs with
          # `abort_on_exception` disabled, so an uncaught error would kill the thread
          # silently and every connection after it would sit in the backlog forever.
          begin
            Steep.logger.info { "Command socket accepted a connection" }

            # `session` is passed as a thread argument: `while` shares its locals across
            # iterations, so a block reading `session` directly would serve the session of a
            # later iteration when the accept loop wins the race against the thread's start,
            # leaving the accepted connection unread.
            Thread.new(Session.new(socket)) do |session|
              Thread.current.abort_on_exception = false
              serve(session)
            end
          rescue StandardError => error
            Steep.logger.error { "Command socket could not serve an accepted connection: #{error.inspect}" }
            begin
              socket.close
            rescue IOError
              # Already closed
            end
          end
        end
      ensure
        Steep.logger.info { "Command socket accept loop finished" }
      end

      def serve(session)
        reader = LSP::Transport::Io::Reader.new(session.socket)
        reader.read do |message|
          Steep.logger.info { "Command socket received message: method=#{message[:method] || "-"}, id=#{message[:id] || "-"}" }
          master.process_command_socket_message(message, session)
        end
      rescue IOError, SystemCallError => error
        Steep.logger.warn { "Command socket client error: #{error.inspect}" }
      ensure
        Steep.logger.info { "Command socket connection closed" }
        master.finish_command_socket_session(session)
        session.close
      end
    end
  end
end
