module Steep
  class Project
    # Project-wide index of forward-delegate methods, used by the
    # `TypeConstruction` to inline calls to such methods for narrowing
    # purposes (felixefelip/steep#32).
    #
    # Built eagerly the first time `Project#delegation_registry` is
    # accessed: walks every Ruby source file in every target via
    # `FileLoader`, parses it, runs `DelegationAnalyzer`, and merges
    # the resulting per-file delegation maps into a single index. The
    # whole registry is rebuilt from scratch whenever any source
    # changes (`Project#invalidate_delegation_registry!`) — coarse
    # invalidation that keeps the model simple at the cost of
    # re-parsing on LSP edits.
    #
    # RBS-only classes (gem_rbs_collection, Rails internals, etc.)
    # are silently ignored — there's no Ruby source to analyze, so
    # no delegation can be detected. Lookup just returns nil and the
    # caller continues with the normal type-send path.
    class DelegationRegistry
      def self.build(project)
        new.tap { |r| r.build(project) }
      end

      def initialize
        @entries = {} #: Hash[String, Hash[Symbol, Steep::TypeInference::DelegationAnalyzer::DelegationInfo]]
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

      # @param class_name [String, #to_s] e.g. `"Concerts::Ticket"` or
      #   an absolute `"::Concerts::Ticket"` (leading `::` is stripped
      #   to match the analyzer's storage format).
      # @param method_name [Symbol, #to_sym]
      # @return [Steep::TypeInference::DelegationAnalyzer::DelegationInfo, nil]
      def lookup(class_name, method_name)
        key = class_name.to_s.sub(/\A::/, "")
        @entries.dig(key, method_name.to_sym)
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

      # Parse a single file and merge its delegations into the index.
      # Failures (syntax errors, encoding, etc.) are logged and the
      # file is skipped — the registry is best-effort, not a hard
      # requirement for type-checking to proceed.
      def ingest(absolute_path)
        content = absolute_path.read
        node = parse(content, absolute_path.to_s)
        return unless node
        delegations = TypeInference::DelegationAnalyzer.analyze(node)
        delegations.each do |class_name, methods|
          @entries[class_name] ||= {}
          methods.each do |method_name, info|
            @entries[class_name][method_name] = info
          end
        end
      rescue StandardError, ::Parser::SyntaxError => e
        Steep.logger.warn { "[delegation_registry] failed to ingest #{absolute_path}: #{e.message}" }
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
