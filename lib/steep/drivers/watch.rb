module Steep
  module Drivers
    class Watch
      attr_reader :dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :queue

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @dirs = []
        @stdout = stdout
        @stderr = stderr
        @queue = Thread::Queue.new
      end

      def listener
        @listener ||= begin
          Steep.logger.info "Watching #{dirs.join(", ")}..."
          Listen.to(*dirs.map(&:to_s)) do |modified, added, removed|
            Steep.logger.tagged "watch" do
              Steep.logger.info "Received file system updates: modified=[#{modified.join(",")}], added=[#{added.join(",")}], removed=[#{removed.join(",")}]"
            end
            queue << [modified, added, removed]
          end
        end
      end

      def type_check_loop(project)
        until queue.closed?
          stdout.puts "🚥 Waiting for updates..."

          events = []
          events << queue.deq
          until queue.empty?
              events << queue.deq(nonblock: true)
          end

          events.compact.each do |modified, added, removed|
            modified.each do |name|
              path = Pathname(name).relative_path_from(Pathname.pwd)

              project.targets.each do |target|
                target.update_source path, path.read if target.source_file?(path)
                target.update_signature path, path.read if target.signature_file?(path)
              end
            end

            added.each do |name|
              path = Pathname(name).relative_path_from(Pathname.pwd)

              project.targets.each do |target|
                target.add_source path, path.read if target.possible_source_file?(path)
                target.add_signature path, path.read if target.possible_signature_file?(path)
              end
            end

            removed.each do |name|
              path = Pathname(name).relative_path_from(Pathname.pwd)

              project.targets.each do |target|
                target.remove_source path if target.source_file?(path)
                target.remove_signature path if target.signature_file?(path)
              end
            end
          end

          stdout.puts "🔬 Type checking..."
          type_check project
          print_project_result project
        end
      rescue ClosedQueueError
        # nop
      end

      def print_project_result(project)
        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            case (status = target.status)
            when Project::Target::SignatureSyntaxErrorStatus
              printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
              printer.print_syntax_errors(status.errors)
            when Project::Target::SignatureValidationErrorStatus
              printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)
              printer.print_semantic_errors(status.errors)
            when Project::Target::TypeCheckStatus
              status.type_check_sources.each do |source_file|
                source_file.errors.each do |error|
                  error.print_to stdout
                end
              end
            end
          end
        end
      end

      def run()
        if dirs.empty?
          stdout.puts "Specify directories to watch"
          return 1
        end

        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources([])
        loader.load_signatures()

        type_check project
        print_project_result project

        listener.start

        stdout.puts "👀 Watching directories, Ctrl-C to stop."
        begin
          type_check_loop project
        rescue Interrupt
          # bye
        end

        0
      end
    end
  end
end
