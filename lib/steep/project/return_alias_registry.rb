module Steep
  class Project
    # Project-wide index of methods that return-alias a reader of their result
    # to a self path (`Proxy#build` returns a record whose `post` is
    # `self.owner`), keyed as `"Class#method" => { reader => [path_syms] }`
    # (felixefelip/steep#62). Consumed via `Contracts::AliasResolver` so a
    # caller's `x = build; x.post.user` is rooted at `self.owner.user`. Built and
    # invalidated like the other source-derived registries.
    class ReturnAliasRegistry
      def self.build(project)
        new.tap { |r| r.build(project) }
      end

      def initialize
        @entries = {} #: Hash[String, Hash[Symbol, Array[Symbol]]]
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

      # @return [Hash[String, Hash[Symbol, Array[Symbol]]]] the raw index, in the
      #   `"Class#method" => { reader => path }` shape `AliasResolver` expects
      def to_h
        @entries
      end

      def empty?
        @entries.empty?
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
        TypeInference::ReturnAliasAnalyzer.analyze(node).each do |key, readers|
          (@entries[key] ||= {}).merge!(readers)
        end
      rescue StandardError, ::Parser::SyntaxError => e
        Steep.logger.warn { "[return_alias_registry] failed to ingest #{absolute_path}: #{e.message}" }
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
