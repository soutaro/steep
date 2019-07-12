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

    class Builder < ::Parser::Builders::Default
      def string_value(token)
        value(token)
      end

      self.emit_lambda = true
      self.emit_procarg0 = true
    end

    def self.parser
      ::Parser::Ruby25.new(Builder.new).tap do |parser|
        parser.diagnostics.all_errors_are_fatal = true
        parser.diagnostics.ignore_warnings = true
      end
    end

    def self.parse(source_code, path:, factory:, labeling: ASTUtils::Labeling.new)
      buffer = ::Parser::Source::Buffer.new(path.to_s, 1)
      buffer.source = source_code
      node = parser.parse(buffer).yield_self do |n|
        if n
          labeling.translate(n, {})
        else
          return
        end
      end

      annotations = []

      _, comments, _ = yield_self do
        buffer = ::Parser::Source::Buffer.new(path.to_s)
        buffer.source = source_code
        parser = ::Parser::Ruby25.new

        parser.tokenize(buffer)
      end

      buffer = AST::Buffer.new(name: path, content: source_code)

      comments.each do |comment|
        src = comment.text.gsub(/\A#\s*/, '')
        location = AST::Location.new(buffer: buffer,
                                     start_pos: comment.location.expression.begin_pos + 1,
                                     end_pos: comment.location.expression.end_pos)
        annotation = AnnotationParser.new(factory: factory).parse(src, location: location)
        if annotation
          annotations << LocatedAnnotation.new(line: comment.location.line, source: src, annotation: annotation)
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

    def self.construct_mapping(node:, annotations:, mapping:, line_range: nil)
      case node.type
      when :if
        if node.loc.is_a?(::Parser::Source::Map::Ternary)
          # Skip ternary operator
          each_child_node node do |child|
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        else
          if node.loc.expression.begin_pos == node.loc.keyword.begin_pos
            construct_mapping(node: node.children[0],
                              annotations: annotations,
                              mapping: mapping,
                              line_range: nil)

            if node.children[1]
              if node.loc.keyword.source == "if" || node.loc.keyword.source == "elsif"
                then_start = node.loc.begin&.loc&.last_line || node.children[0].loc.last_line
                then_end = node.children[2] ? node.loc.else.line : node.loc.last_line
              else
                then_start = node.loc.else.last_line
                then_end = node.loc.last_line
              end
              construct_mapping(node: node.children[1],
                                annotations: annotations,
                                mapping: mapping,
                                line_range: then_start...then_end)
            end

            if node.children[2]
              if node.loc.keyword.source == "if" || node.loc.keyword.source == "elsif"
                else_start = node.loc.else.last_line
                else_end = node.loc.last_line
              else
                else_start = node.loc.begin&.last_line || node.children[0].loc.last_line
                else_end = node.children[1] ? node.loc.else.line : node.loc.last_line
              end
              construct_mapping(node: node.children[2],
                                annotations: annotations,
                                mapping: mapping,
                                line_range: else_start...else_end)
            end

          else
            # postfix if/unless
            each_child_node(node) do |child|
              construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
            end
          end
        end

      when :while, :until
        if node.loc.expression.begin_pos == node.loc.keyword.begin_pos
          construct_mapping(node: node.children[0],
                            annotations: annotations,
                            mapping: mapping,
                            line_range: nil)

          if node.children[1]
            body_start = node.children[0].loc.last_line
            body_end = node.loc.end.line

            construct_mapping(node: node.children[1],
                              annotations: annotations,
                              mapping: mapping,
                              line_range: body_start...body_end)
          end

        else
          # postfix while
          each_child_node(node) do |child|
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        end

      when :while_post, :until_post
        construct_mapping(node: node.children[0],
                          annotations: annotations,
                          mapping: mapping,
                          line_range: nil)

        if node.children[1]
          body_start = node.loc.expression.line
          body_end = node.loc.keyword.line

          construct_mapping(node: node.children[1],
                            annotations: annotations,
                            mapping: mapping,
                            line_range: body_start...body_end)
        end

      when :case
        if node.children[0]
          construct_mapping(node: node.children[0], annotations: annotations, mapping: mapping, line_range: nil)
        end

        if node.loc.else
          else_node = node.children.last
          else_start = node.loc.else.last_line
          else_end = node.loc.end.line

          construct_mapping(node: else_node,
                            annotations: annotations,
                            mapping: mapping,
                            line_range: else_start...else_end)
        end

        node.children.drop(1).each do |child|
          if child&.type == :when
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        end

      when :when
        last_cond = node.children[-2]
        body = node.children.last

        node.children.take(node.children.size-1) do |child|
          construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
        end

        if body
          cond_end = last_cond.loc.last_line+1
          body_end = body.loc.last_line
          construct_mapping(node: body,
                            annotations: annotations,
                            mapping: mapping,
                            line_range: cond_end...body_end)
        end

      when :rescue
        if node.children.last
          else_node = node.children.last
          else_start = node.loc.else.last_line
          else_end = node.loc.last_line

          construct_mapping(node: else_node,
                            annotations: annotations,
                            mapping: mapping,
                            line_range: else_start...else_end)
        end

        each_child_node(node) do |child|
          construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
        end

      else
        each_child_node(node) do |child|
          construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
        end
      end

      associated_annotations = annotations.select do |annot|
        case node.type
        when :def, :module, :class, :block, :ensure, :defs
          loc = node.loc
          loc.line <= annot.line && annot.line < loc.last_line

        when :resbody
          if node.loc.keyword.begin_pos == node.loc.expression.begin_pos
            # skip postfix rescue
            loc = node.loc
            loc.line <= annot.line && annot.line < loc.last_line
          end
        else
          if line_range
            line_range.begin <= annot.line && annot.line < line_range.end
          end
        end
      end

      associated_annotations.each do |annot|
        mapping[node.__id__] = [] unless mapping.key?(node.__id__)
        mapping[node.__id__] << annot.annotation
        annotations.delete annot
      end
    end

    def self.each_child_node(node)
      node.children.each do |child|
        if child.is_a?(::AST::Node)
          yield child
        end
      end
    end

    def annotations(block:, factory:, current_module:)
      AST::Annotation::Collection.new(
        annotations: mapping[block.__id__] || [],
        factory: factory,
        current_module: current_module
      )
    end

    def each_annotation
      if block_given?
        mapping.each_key do |id|
          node = ObjectSpace._id2ref(id)
          yield node, mapping[id]
        end
      else
        enum_for :each_annotation
      end
    end

    # @type method find_node: (line: Integer, column: Integer, ?node: any, ?position: Integer?) -> any
    def find_node(line:, column:, node: self.node, position: nil)
      position ||= (line-1).times.sum do |i|
        node.location.expression.source_buffer.source_line(i+1).size + 1
      end + column

      range = node.location.expression&.yield_self do |r|
        r.begin_pos..r.end_pos
      end

      if range
        if range === position
          Source.each_child_node(node) do |child|
            n = find_node(line: line, column: column, node: child, position: position)
            if n
              return n
            end
          end

          node
        end
      end
    end
  end
end
