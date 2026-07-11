module Steep
  class Project
    # Project-wide index mapping each class's attr-style reader methods to the
    # constructor parameter index their backing ivar is assigned from. Consumed
    # by `TypeConstruction` at `.new` call sites to translate an `initialize`
    # precondition on `self.<reader>...` into an obligation on the matching
    # constructor argument (felixefelip/steep#60).
    #
    # Built and invalidated exactly like `DelegationRegistry`: a full source
    # sweep on first access, rebuilt from scratch on any source change. RBS-only
    # classes have no Ruby body to analyze and are simply absent — `lookup`
    # returns nil and the caller falls through.
    class ConstructorBindingRegistry
      def self.build(project)
        new.tap { |r| r.build(project) }
      end

      def initialize
        @entries = {} #: Hash[String, Hash[Symbol, Integer]]
      end

      # @return self
      def build(project)
        loader = Services::FileLoader.new(base_dir: project.base_dir)
        project.targets.each do |target|
          loader.each_path_in_target(target) do |relative_path|
            absolute = project.absolute_path(relative_path)
            next unless absolute.file?
            next unless ruby_source?(absolute)
            ingest(absolute)
          end
        end
        @entries.freeze
        self
      end

      # @param class_name [String, #to_s] absolute (`"::Proxy"`) or bare
      # @param reader [Symbol, #to_sym]
      # @return [Integer, nil] the constructor parameter index, or nil
      def lookup(class_name, reader)
        key = class_name.to_s.sub(/\A::/, "")
        @entries.dig(key, reader.to_sym)
      end

      # @param class_name [String, #to_s]
      # @return [Hash[Symbol, Integer], nil] all reader→index bindings for the
      #   class, or nil when it has none
      def bindings_for(class_name)
        @entries[class_name.to_s.sub(/\A::/, "")]
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

      def ingest(absolute_path)
        content = absolute_path.read
        node = parse(content, absolute_path.to_s)
        return unless node
        bindings = TypeInference::ConstructorBindingAnalyzer.analyze(node)
        bindings.each do |class_name, readers|
          (@entries[class_name] ||= {}).merge!(readers)
        end
      rescue StandardError, ::Parser::SyntaxError => e
        Steep.logger.warn { "[constructor_binding_registry] failed to ingest #{absolute_path}: #{e.message}" }
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
