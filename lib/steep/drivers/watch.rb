module Steep
  module Drivers
    class Watch
      class Options
        attr_accessor :fallback_any_is_error
        attr_accessor :allow_missing_definitions

        def initialize
          self.fallback_any_is_error = false
          self.allow_missing_definitions = true
        end
      end

      attr_reader :source_dirs
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :options
      attr_reader :queue

      include Utils::EachSignature

      def initialize(source_dirs:, signature_dirs:, stdout:, stderr:)
        @source_dirs = source_dirs
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr
        @options = Options.new
        @queue = Thread::Queue.new
      end

      def project_options
        Project::Options.new.tap do |opt|
          opt.fallback_any_is_error = options.fallback_any_is_error
          opt.allow_missing_definitions = options.allow_missing_definitions
        end
      end

      def source_listener
        @source_listener ||= yield_self do
          Listen.to(*source_dirs.map(&:to_s), only: /\.rb$/) do |modified, added, removed|
            queue << [:source, modified, added, removed]
          end
        end
      end

      def signature_listener
        @signature_listener ||= yield_self do
          Listen.to(*signature_dirs.map(&:to_s), only: /\.rbi$/) do |modified, added, removed|
            queue << [:signature, modified, added, removed]
          end
        end
      end

      def type_check_thread(project)
        Thread.new do
          until queue.closed?
            begin
              events = []
              events << queue.deq
              until queue.empty?
                events << queue.deq(nonblock: true)
              end

              events.compact.each do |name, modified, added, removed|
                case name
                when :source
                  (modified + added).each do |name|
                    path = Pathname(name).relative_path_from(Pathname.pwd)
                    file = project.source_files[path] || Project::SourceFile.new(path: path, options: project_options)
                    file.content = path.read
                    project.source_files[path] = file
                  end

                  removed.each do |name|
                    path = Pathname(name).relative_path_from(Pathname.pwd)
                    project.source_files.delete(path)
                  end

                when :signature
                  (modified + added).each do |name|
                    path = Pathname(name).relative_path_from(Pathname.pwd)
                    file = project.signature_files[path] || Project::SignatureFile.new(path: path)
                    file.content = path.read
                    project.signature_files[path] = file
                  end

                  removed.each do |name|
                    path = Pathname(name).relative_path_from(Pathname.pwd)
                    project.signature_files.delete(path)
                  end
                end
              end

              begin
                project.type_check
              rescue Racc::ParseError => exn
                stderr.puts exn.message
                project.clear
              end
            end
          end
        rescue ClosedQueueError
          # nop
        end
      end

      class WatchListener < Project::NullListener
        attr_reader :stdout
        attr_reader :stderr

        def initialize(stdout:, stderr:, verbose:)
          @stdout = stdout
          @stderr = stderr
        end

        def check(project:)
          yield.tap do
            if project.success?
              if project.has_type_error?
                stdout.puts "Detected #{project.errors.size} errors... 🔥"
              else
                stdout.puts "No error detected. 🎉"
              end
            else
              stdout.puts "Type checking failed... 🔥"
            end
          end
        end

        def type_check_source(project:, file:)
          yield.tap do
            case
            when file.source.is_a?(Source) && file.errors
              file.errors.each do |error|
                error.print_to stdout
              end
            end
          end
        end

        def load_signature(project:)
          # @type var project: Project
          yield.tap do
            case sig = project.signature
            when Project::SignatureHasError
            when Project::SignatureHasSyntaxError
              sig.errors.each do |path, exn|
                stdout.puts "#{path} has a syntax error: #{exn.inspect}"
              end
            end
          end
        end
      end

      def run(block: true)
        project = Project.new(WatchListener.new(stdout: stdout, stderr: stderr, verbose: false))

        source_dirs.each do |path|
          each_file_in_path(".rb", path) do |file_path|
            file = Project::SourceFile.new(path: file_path, options: options)
            file.content = file_path.read
            project.source_files[file_path] = file
          end
        end

        signature_dirs.each do |path|
          each_file_in_path(".rbi", path) do |file_path|
            file = Project::SignatureFile.new(path: file_path)
            file.content = file_path.read
            project.signature_files[file_path] = file
          end
        end

        project.type_check

        source_listener.start
        signature_listener.start
        t = type_check_thread(project)

        binding.pry(quiet: true) if block

        queue.close
        t.join
      end
    end
  end
end
