module Steep
  module Drivers
    class Annotations
      attr_reader :source_paths
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :labeling

      include Utils::EachSignature

      def initialize(source_paths:, stdout:, stderr:)
        @source_paths = source_paths
        @stdout = stdout
        @stderr = stderr

        @labeling = ASTUtils::Labeling.new
      end

      def run
        each_ruby_source(source_paths, false) do |source|
          source.each_annotation.sort_by {|node, _| [node.loc.expression.begin_pos, node.loc.expression.end_pos] }.each do |node, annotations|
            loc = node.loc
            stdout.puts "#{source.path}:#{loc.line}:#{loc.column}:#{node.type}:\t#{node.loc.expression.source.lines.first}"
            annotations.each do |annotation|
              stdout.puts "  #{annotation.location.source}"
            end
          end
        end

        0
      end
    end
  end
end
