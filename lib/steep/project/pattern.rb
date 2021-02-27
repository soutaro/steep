module Steep
  class Project
    class Pattern
      attr_reader :patterns
      attr_reader :ignores
      attr_reader :prefixes
      attr_reader :ignore_prefixes
      attr_reader :ext

      def initialize(patterns:, ignores: [], ext:)
        @patterns = patterns
        @ignores = ignores
        @ext = ext

        @prefixes = patterns.map do |pat|
          pat.delete_prefix("./").delete_suffix(File::Separator) << File::Separator
        end
        @ignore_prefixes = ignores.map do |prefix|
          prefix.delete_prefix("./").delete_suffix(File::Separator) << File::Separator
        end
      end

      def =~(path)
        unless path.is_a?(Pathname)
          path = Pathname(path.to_s)
        end

        match?(path) && !ignore?(path)
      end

      def match?(path)
        test_string(path, patterns, prefixes)
      end

      def ignore?(path)
        test_string(path, ignores, ignore_prefixes)
      end

      def test_string(path, patterns, prefixes)
        string = path.to_s
        extension = path.extname

        patterns.any? {|pat| File.fnmatch(pat, string) } ||
          prefixes.any? {|prefix| string.start_with?(prefix) && extension == ext }
      end
    end
  end
end
