module Steep
  module Drivers
    class Annotations
      attr_reader :command_line_patterns
      attr_reader :stdout
      attr_reader :stderr

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr

        @command_line_patterns = []
      end

      def run
        project = load_config()

        loader = Services::FileLoader.new(base_dir: project.base_dir)

        project.targets.each do |target|
          Steep.logger.tagged "target=#{target.name}" do
            service = Services::SignatureService.load_from(target.new_env_loader(project: project))

            sigs = loader.load_changes(target.signature_pattern, changes: {})
            service.update(sigs)

            factory = AST::Types::Factory.new(builder: service.latest_builder)

            srcs = loader.load_changes(target.source_pattern, command_line_patterns, changes: {})
            srcs.each do |path, changes|
              text = changes.inject("") {|text, change| change.apply_to(text) }
              source = Source.parse(text, path: path, factory: factory)

              source.each_annotation.sort_by {|node, _| [node.loc.expression.begin_pos, node.loc.expression.end_pos] }.each do |node, annotations|
                loc = node.loc
                stdout.puts "#{path}:#{loc.line}:#{loc.column}:#{node.type}:\t#{node.loc.expression.source.lines.first}"
                annotations.each do |annotation|
                  annotation.location or raise
                  stdout.puts "  #{annotation.location.source}"
                end
              end
            end
          end
        end

        0
      end
    end
  end
end
