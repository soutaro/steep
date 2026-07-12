module Steep
  class Project
    # Project-wide index of "return-forwarding" methods: a method whose return
    # value constructs an owner-capturing proxy, mapped to the proxy readers
    # that are the call's own receiver (felixefelip/steep#62).
    #
    #   { "Post#assignments" => Set[:owner] }   # post.assignments.owner == post
    #
    # Consumed by `TypeConstruction` to collapse `<recv>.<method>.<reader>` back
    # to `<recv>` when discharging a precondition. Built on top of the
    # `ConstructorBindingRegistry` (reader→param index) and invalidated with the
    # rest of the source-derived registries.
    class ReturnForwardingRegistry
      def self.build(project, constructor_bindings)
        new.tap { |r| r.build(project, constructor_bindings) }
      end

      def initialize
        @entries = {} #: Hash[String, Set[Symbol]]
      end

      # @return self
      def build(project, constructor_bindings)
        loader = Services::FileLoader.new(base_dir: project.base_dir)
        project.targets.each do |target|
          loader.each_path_in_target(target) do |relative_path|
            absolute = project.absolute_path(relative_path)
            next unless absolute.file?
            next unless ruby_source?(absolute)
            ingest(absolute, constructor_bindings)
          end
        end
        @entries.freeze
        self
      end

      # @param class_name [String, #to_s]
      # @param method [Symbol, #to_sym]
      # @return [Set[Symbol], nil] the readers of the returned proxy that equal
      #   the call's receiver, or nil when the method does not forward
      def lookup(class_name, method)
        @entries["#{class_name.to_s.sub(/\A::/, "")}##{method}"]
      end

      def empty?
        @entries.empty?
      end

      def to_h
        @entries
      end

      private

      def ruby_source?(path)
        ext = path.extname
        ext == ".rb" || ext == ".rake"
      end

      def ingest(absolute_path, constructor_bindings)
        content = absolute_path.read
        node = parse(content, absolute_path.to_s)
        return unless node
        forwards = TypeInference::ReturnForwardingAnalyzer.analyze(node, constructor_bindings: constructor_bindings)
        forwards.each do |key, readers|
          (@entries[key] ||= Set.new).merge(readers)
        end
      rescue StandardError, ::Parser::SyntaxError => e
        Steep.logger.warn { "[return_forwarding_registry] failed to ingest #{absolute_path}: #{e.message}" }
      end

      def parse(content, path_name)
        buffer = ::Parser::Source::Buffer.new(path_name)
        buffer.source = content
        parser = ::Parser::Ruby33.new
        parser.diagnostics.all_errors_are_fatal = false
        parser.diagnostics.ignore_warnings = true
        parser.parse(buffer)
      rescue ::Parser::SyntaxError
        nil
      end
    end
  end
end
