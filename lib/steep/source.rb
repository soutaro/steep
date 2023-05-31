module Steep
  class Source
    attr_reader :path
    attr_reader :node
    attr_reader :mapping

    extend NodeHelper

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
      self.emit_kwargs = true
      self.emit_forward_arg = true
    end

    def self.new_parser
      ::Parser::Ruby32.new(Builder.new).tap do |parser|
        parser.diagnostics.all_errors_are_fatal = true
        parser.diagnostics.ignore_warnings = true
      end
    end

    def self.parse(source_code, path:, factory:)
      buffer = ::Parser::Source::Buffer.new(path.to_s, 1, source: source_code)
      node, comments = new_parser().parse_with_comments(buffer)

      # @type var annotations: Array[AST::Annotation::t]
      annotations = []
      # @type var type_comments: Hash[Integer, type_comment]
      type_comments = {}

      buffer = RBS::Buffer.new(name: path, content: source_code)
      annotation_parser = AnnotationParser.new(factory: factory)

      comments.each do |comment|
        if comment.inline?
          content = comment.text.delete_prefix('#')
          content.lstrip!
          prefix = comment.text.size - content.size
          content.rstrip!
          suffix = comment.text.size - content.size - prefix

          location = RBS::Location.new(
            buffer: buffer,
            start_pos: comment.location.expression.begin_pos + prefix,
            end_pos: comment.location.expression.end_pos - suffix
          )

          case
          when annotation = annotation_parser.parse(content, location: location)
            annotations << annotation
          when assertion = AST::Node::TypeAssertion.parse(location)
            type_comments[assertion.line] = assertion
          when tapp = AST::Node::TypeApplication.parse(location)
            type_comments[tapp.line] = tapp
          end
        end
      end

      map = {}
      map.compare_by_identity

      if node
        node = insert_type_node(node, type_comments)
        construct_mapping(node: node, annotations: annotations, mapping: map)
      end

      annotations.each do |annot|
        map[node] ||= []
        map[node] << annot
      end

      new(path: path, node: node, mapping: map)
    end

    def self.construct_mapping(node:, annotations:, mapping:, line_range: nil)
      case node.type
      when :if
        if node.loc.respond_to?(:question)
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
                then_start = node.loc.begin&.last_line || node.children[0].loc.last_line
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

        if node.children.last
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

        node.children.take(node.children.size-1).each do |child|
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

      associated_annotations, other_annotations = annotations.partition do |annot|
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
        mapping[node] ||= []
        mapping[node] << annot
      end

      annotations.replace(other_annotations)
    end

    def self.map_child_node(node, type = nil, skip: nil)
      children = node.children.map do |child|
        if child.is_a?(Parser::AST::Node)
          if skip
            if skip.member?(child)
              child
            else
              yield child
            end
          else
            yield child
          end
        else
          child
        end
      end

      node.updated(type, children)
    end

    def annotations(block:, factory:, context:)
      AST::Annotation::Collection.new(
        annotations: (mapping[block] || []),
        factory: factory,
        context: context
      )
    end

    def each_annotation(&block)
      if block_given?
        mapping.each do |node, annots|
          yield [node, annots]
        end
      else
        enum_for :each_annotation
      end
    end

    def each_heredoc_node(node = self.node, parents = [], &block)
      if block
        return unless node

        case node.type
        when :dstr, :str
          if node.location.respond_to?(:heredoc_body)
            yield [node, *parents]
          end
        end

        parents.unshift(node)
        Source.each_child_node(node) do |child|
          each_heredoc_node(child, parents, &block)
        end
        parents.shift()
      else
        enum_for :each_heredoc_node, node
      end
    end

    def find_heredoc_nodes(line, column, position)
      each_heredoc_node() do |nodes|
        node = nodes[0]

        range = node.location.heredoc_body&.yield_self do |r|
          r.begin_pos..r.end_pos
        end

        if range && (range === position)
          return nodes
        end
      end

      nil
    end

    def find_nodes_loc(node, position, parents)
      range = node.location.expression&.yield_self do |r|
        r.begin_pos..r.end_pos
      end

      if range
        if range === position
          parents.unshift node

          Source.each_child_node(node) do |child|
            if ns = find_nodes_loc(child, position, parents)
              return ns
            end
          end

          parents
        end
      end
    end

    def find_nodes(line:, column:)
      return [] unless node

      position = (line-1).times.sum do |i|
        node.location.expression.source_buffer.source_line(i+1).size + 1
      end + column

      if heredoc_nodes = find_heredoc_nodes(line, column, position)
        Source.each_child_node(heredoc_nodes[0]) do |child|
          if nodes = find_nodes_loc(child, position, heredoc_nodes)
            return nodes
          end
        end

        return heredoc_nodes
      else
        find_nodes_loc(node, position, [])
      end
    end

    def self.delete_defs(node, allow_list)
      case node.type
      when :def
        if allow_list.include?(node)
          node
        else
          node.updated(:nil, [])
        end
      when :defs
        if allow_list.include?(node)
          node
        else
          delete_defs(node.children[0], allow_list)
        end
      else
        map_child_node(node) do |child|
          delete_defs(child, allow_list)
        end
      end
    end

    def without_unrelated_defs(line:, column:)
      if node
        nodes = find_nodes(line: line, column: column) || []
        defs = Set[].compare_by_identity.merge(nodes.select {|node| node.type == :def || node.type == :defs })

        node_ = Source.delete_defs(node, defs)

        # @type var mapping: Hash[Parser::AST::Node, Array[AST::Annotation::t]]
        mapping = {}
        mapping.compare_by_identity

        annotations = self.mapping.values.flatten
        Source.construct_mapping(node: node_, annotations: annotations, mapping: mapping)

        annotations.each do |annot|
          mapping[node_] ||= []
          mapping[node_] << annot
        end

        Source.new(path: path, node: node_, mapping: mapping)
      else
        self
      end
    end

    def self.insert_type_node(node, comments)
      if node.location.expression
        first_line = node.location.expression.first_line
        last_line = node.location.expression.last_line
        last_comment = comments[last_line]

        if (first_line..last_line).none? {|l| comments.key?(l) }
          return node
        end

        case
        when last_comment.is_a?(AST::Node::TypeAssertion)
          case node.type
          when :lvasgn, :ivasgn, :gvasgn, :cvasgn, :casgn
            # Skip
          when :masgn
            lhs, rhs = node.children
            node = node.updated(nil, [lhs, insert_type_node(rhs, comments)])
            return adjust_location(node)
          when :return, :break, :next
            # Skip
          when :begin
            if node.loc.begin
              # paren
              child_assertions = comments.except(last_line)
              node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }
              node = adjust_location(node)
              return assertion_node(node, last_comment)
            end
          else
            child_assertions = comments.except(last_line)
            node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }
            node = adjust_location(node)
            return assertion_node(node, last_comment)
          end
        when selector_line = sendish_node?(node)
          if (comment = comments[selector_line]).is_a?(AST::Node::TypeApplication)
            child_assertions = comments.except(selector_line)
            case node.type
            when :block
              send, *children = node.children
              node = node.updated(
                nil,
                [
                  map_child_node(send) {|child| insert_type_node(child, child_assertions) },
                  *children.map {|child| insert_type_node(child, child_assertions) }
                ]
              )
            when :numblock
              send, size, body = node.children
              node = node.updated(
                nil,
                [
                  map_child_node(send) {|child| insert_type_node(child, child_assertions) },
                  size,
                  insert_type_node(body, child_assertions)
                ]
              )
            else
              node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }
            end
            node = adjust_location(node)
            return type_application_node(node, comment)
          end
        end
      end

      case node.type
      when :class
        class_name, super_class, class_body = node.children
        adjust_location(
          node.updated(
            nil,
            [
              class_name,
              super_class,
              class_body ? insert_type_node(class_body, comments) : nil
            ]
          )
        )
      when :module
        module_name, module_body = node.children
        adjust_location(
          node.updated(
            nil,
            [
              module_name,
              module_body ? insert_type_node(module_body, comments) : nil
            ]
          )
        )
      else
        adjust_location(
          map_child_node(node, nil) {|child| insert_type_node(child, comments) }
        )
      end
    end

    def self.sendish_node?(node)
      send_node =
        case node.type
        when :send, :csend
          node
        when :block, :numblock
          send = node.children[0]
          case send.type
          when :send, :csend
            send
          end
        end

      if send_node
        if send_node.location.dot
          send_node.location.selector.line
        end
      end
    end

    def self.adjust_location(node)
      if end_pos = node.location.expression&.end_pos
        if last_pos = each_child_node(node).map {|node| node.location.expression&.end_pos }.compact.max
          if last_pos > end_pos
            props = { location: node.location.with_expression(node.location.expression.with(end_pos: last_pos)) }
          end
        end
      end

      if props
        node.updated(nil, nil, props)
      else
        node
      end
    end

    def self.assertion_node(node, type)
      map = Parser::Source::Map.new(node.location.expression.with(end_pos: type.location.end_pos))
      Parser::AST::Node.new(:assertion, [node, type], { location: map })
    end

    def self.type_application_node(node, tapp)
      if node.location.expression.end_pos > tapp.location.end_pos
        map = Parser::Source::Map.new(node.location.expression)
      else
        map = Parser::Source::Map.new(node.location.expression.with(end_pos: tapp.location.end_pos))
      end

      node = Parser::AST::Node.new(:tapp, [node, tapp], { location: map })
      tapp.set_node(node)
      node
    end
  end
end
