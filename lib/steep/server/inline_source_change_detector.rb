module Steep
  module Server
    class InlineSourceChangeDetector
      class Source
        attr_reader :content
        attr_reader :changes
        attr_reader :last_fingerprint

        def initialize(content)
          @content = content
          @changes = []
          update_fingerprint!
        end

        def <<(changes)
          @changes << changes
        end

        def updated?
          if changes.empty?
            return false
          end

          updated_content = changes.inject(content) do |current_content, change|
            change.apply_to(current_content)
          end
          changes.clear

          if updated_content == content
            return false
          end

          @content = updated_content

          update_fingerprint!
        end

        def update_fingerprint!
          buffer = RBS::Buffer.new(name: Pathname("test.rb"), content: content)
          prism = Prism.parse(content)
          result = RBS::InlineParser.parse(buffer, prism)

          new_fingerprint = result.type_fingerprint

          (new_fingerprint != last_fingerprint).tap do
            @last_fingerprint = new_fingerprint
          end
        end

        def clear
          @changes.clear
        end
      end

      attr_reader :sources

      def initialize
        @sources = {}
      end

      def add_source(path, content)
        sources.key?(path) and raise "Source already exists for #{path}"
        sources[path] = Source.new(content)
      end

      def replace_source(path, content)
        source = sources.fetch(path)
        if source.content == content
          source.clear
        else
          source << Services::ContentChange.string(content)
        end
      end

      def accumulate_change(file_path, changes)
        changes.each do |change|
          sources.fetch(file_path) << change
        end
      end

      def type_updated_paths(paths)
        paths.select { sources[_1]&.updated? }.to_set
      end

      def has_source?(path)
        sources.key?(path)
      end

      def reset
        sources.each_value { _1.updated? }
      end
    end
  end
end
