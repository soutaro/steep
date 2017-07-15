module Steep
  class Source
    class LocatedAnnotation
      attr_reader :line
      attr_reader :annotation
      attr_reader :source

      def initialize(line:, source:, annotation:)
        @line = line
        @source = source
        @annotation = annotation
      end

      def ==(other)
        other.is_a?(LocatedAnnotation) &&
          other.line == line &&
          other.annotation == annotation
      end
    end

    attr_reader :path
    attr_reader :node
    attr_reader :mapping

    def initialize(path:, node:, mapping:)
      @path = path
      @node = node
      @mapping = mapping
    end

    def self.parse(source_code, path:, labeling: ASTUtils::Labeling.new)
      node = labeling.translate(::Parser::CurrentRuby.parse(source_code, path.to_s), {})

      annotations = []

      source_code.each_line.with_index(1) do |line, index|
        if line =~ /#(.+)/
          source = $1
          annotation = Steep::Parser.parse_annotation_opt(source)
          if annotation
            annotations << LocatedAnnotation.new(line: index, source: source, annotation: annotation)
          end
        end
      end

      mapping = {}
      construct_mapping(node: node, annotations: annotations, mapping: mapping)

      annotations.each do |annot|
        mapping[node.__id__] = [] unless mapping.key?(node.__id__)
        mapping[node.__id__] << annot.annotation
      end

      new(path: path, node: node, mapping: mapping)
    end

    def self.construct_mapping(node:, annotations:, mapping:)
      each_child_node(node) do |child|
        construct_mapping(node: child, annotations: annotations, mapping: mapping)
      end

      case node.type
      when :def, :block, :module, :class, :begin
        start_line = node.loc.line
        end_line = node.loc.last_line

        consumed = []

        annotations.each do |annot|
          if start_line <= annot.line && annot.line < end_line
            consumed << annot
            mapping[node.__id__] = [] unless mapping.key?(node.__id__)
            mapping[node.__id__] << annot.annotation
          end
        end

        consumed.each do |annot|
          annotations.delete annot
        end
      end
    end

    def self.each_child_node(node)
      node.children.each do |child|
        if child.is_a?(AST::Node)
          yield child
        end
      end
    end

    def annotations(block:)
      mapping[block.__id__]
    end
  end
end
