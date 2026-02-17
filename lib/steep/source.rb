module Steep
  class Source
    attr_reader :buffer
    attr_reader :path
    attr_reader :node
    attr_reader :mapping
    attr_reader :comments
    attr_reader :ignores

    extend NodeHelper
    extend ModuleHelper

    def initialize(buffer:, path:, node:, mapping:, comments:, ignores:)
      @buffer = buffer
      @path = path
      @node = node
      @mapping = mapping
      @comments = comments
      @ignores = ignores
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
      ::Parser::Ruby33.new(Builder.new).tap do |parser|
        parser.diagnostics.all_errors_are_fatal = true
        parser.diagnostics.ignore_warnings = true
      end
    end

    def self.parse(source_code, path:, factory:)
      source_code = ErbToRubyCode.convert(source_code) if path.to_s.end_with?(".erb")

      buffer = ::Parser::Source::Buffer.new(path.to_s, 1, source: source_code)
      node, comments = new_parser().parse_with_comments(buffer)

      # @type var annotations: Array[AST::Annotation::t]
      annotations = []
      # @type var type_comments: Hash[Integer, type_comment]
      type_comments = {}

      buffer = RBS::Buffer.new(name: path, content: source_code)
      annotation_parser = AnnotationParser.new(factory: factory)

      comments = comments.sort_by do |comment|
        comment.loc.expression.begin_pos
      end

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

      map = {} #: Hash[Parser::AST::Node, Array[AST::Annotation::t]]
      map.compare_by_identity

      if node
        node = insert_type_node(node, type_comments)
        construct_mapping(node: node, annotations: annotations, mapping: map)
      end

      annotations.each do |annot|
        map[node] ||= []
        map.fetch(node) << annot
      end

      ignores = comments.filter_map do |comment|
        AST::Ignore.parse(comment, buffer)
      end

      new(buffer: buffer, path: path, node: node, mapping: map, comments: comments, ignores: ignores)
    end

    def self.construct_mapping(node:, annotations:, mapping:, line_range: nil)
      case node.type
      when :if
        cond_node, truthy_node, falsy_node, loc = deconstruct_if_node!(node)

        if node.loc.respond_to?(:question)
          # Skip ternary operator

          each_child_node node do |child|
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        else
          if_loc = loc #: NodeHelper::condition_loc

          if if_loc.expression.begin_pos == if_loc.keyword.begin_pos
            construct_mapping(node: cond_node,annotations: annotations, mapping: mapping, line_range: nil)

            if truthy_node
              if if_loc.keyword.source == "if" || if_loc.keyword.source == "elsif"
                # if foo
                #   bar      <=
                # end
                then_start = if_loc.begin&.last_line || cond_node.loc.last_line
                then_end = if_loc.else&.line || if_loc.last_line
              else
                # unless foo
                # else
                #   bar      <=
                # end
                if_loc.else or raise
                then_start = if_loc.else.last_line
                then_end = loc.last_line
              end
              construct_mapping(node: truthy_node, annotations: annotations, mapping: mapping, line_range: then_start...then_end)
            end

            if falsy_node
              if if_loc.keyword.source == "if" || if_loc.keyword.source == "elsif"
                # if foo
                # else
                #   bar      <=
                # end
                if_loc.else or raise
                else_start = if_loc.else.last_line
                else_end = if_loc.last_line
              else
                # unless foo
                #   bar      <=
                # end
                else_start = if_loc.begin&.last_line || cond_node.loc.last_line
                else_end = if_loc.else&.line || if_loc.last_line
              end
              construct_mapping(node: falsy_node, annotations: annotations, mapping: mapping, line_range: else_start...else_end)
            end

          else
            # postfix if/unless
            each_child_node(node) do |child|
              construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
            end
          end
        end

      when :while, :until
        cond_node, body_node, loc = deconstruct_whileish_node!(node)

        if loc.expression.begin_pos == loc.keyword.begin_pos
          # prefix while
          loc.end or raise
          construct_mapping(node: cond_node, annotations: annotations, mapping: mapping, line_range: nil)

          if body_node
            body_start = cond_node.loc.last_line
            body_end = loc.end.line

            construct_mapping(node: body_node, annotations: annotations, mapping: mapping, line_range: body_start...body_end)
          end
        else
          # postfix while
          each_child_node(node) do |child|
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        end

      when :while_post, :until_post
        cond_node, body_node, loc = deconstruct_whileish_node!(node)

        construct_mapping(node: cond_node, annotations: annotations, mapping: mapping, line_range: nil)

        if body_node
          body_start = loc.expression.line
          body_end = loc.keyword.line
          construct_mapping(node: body_node, annotations: annotations, mapping: mapping, line_range: body_start...body_end)
        end

      when :case
        cond_node, when_nodes, else_node, loc = deconstruct_case_node!(node)

        if cond_node
          construct_mapping(node: cond_node, annotations: annotations, mapping: mapping, line_range: nil)
        end

        if else_node
          loc.else or raise
          loc.end or raise

          else_start = loc.else.last_line
          else_end = loc.end.line

          construct_mapping(node: else_node, annotations: annotations, mapping: mapping, line_range: else_start...else_end)
        end

        when_nodes.each do |child|
          if child.type == :when
            construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
          end
        end

      when :when
        operands, body, loc = deconstruct_when_node!(node)
        last_cond = operands.last or raise

        operands.each do |child|
          construct_mapping(node: child, annotations: annotations, mapping: mapping, line_range: nil)
        end

        if body
          cond_end = loc.begin&.last_line || last_cond.loc.last_line+1
          body_end = body.loc.last_line
          construct_mapping(node: body, annotations: annotations, mapping: mapping, line_range: cond_end...body_end)
        end

      when :rescue
        body, resbodies, else_node, loc = deconstruct_rescue_node!(node)

        if else_node
          loc.else or raise

          else_start = loc.else.last_line
          else_end = loc.last_line

          construct_mapping(node: else_node, annotations: annotations, mapping: mapping, line_range: else_start...else_end)
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
        location = node.loc
        annot.line or next

        case node.type
        when :def, :module, :class, :block, :numblock, :ensure, :defs, :resbody
          location = node.loc
          location.line <= annot.line && annot.line < location.last_line
        else
          if line_range
            line_range.begin <= annot.line && annot.line < line_range.end
          end
        end
      end

      associated_annotations.each do |annot|
        mapping[node] ||= []
        mapping.fetch(node) << annot
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
      annotations =
        if block
          mapping.fetch(block, [])
        else
          []
        end #: Array[AST::Annotation::t]
      AST::Annotation::Collection.new(
        annotations: annotations,
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

    def each_block_annotation(node, &block)
      if block
        if annots = mapping.fetch(node, nil)
          annots.each(&block)
        end
      else
        enum_for :each_block_annotation, node
      end
    end

    def find_block_node(nodes)
      nodes.find { mapping.key?(_1) }
    end

    def each_heredoc_node(node = self.node, parents = [], &block)
      if block
        return unless node

        case node.type
        when :dstr, :str
          if node.location.respond_to?(:heredoc_body)
            yield [[node, *parents], _ = node.location]
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
      each_heredoc_node() do |nodes, location|
        node = nodes[0]
        loc = location.heredoc_body #: Parser::Source::Range

        if range = loc.to_range
          if range.begin <= position && position <= range.end
            return nodes
          end
        end
      end

      nil
    end

    def find_nodes_loc(node, position, parents)
      range = node.location.expression&.to_range

      if range
        if range.begin <= position && position <= range.end
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

      position = buffer.loc_to_pos([line, column])

      if heredoc_nodes = find_heredoc_nodes(line, column, position)
        Source.each_child_node(heredoc_nodes.fetch(0)) do |child|
          if nodes = find_nodes_loc(child, position, heredoc_nodes)
            return nodes
          end
        end

        return heredoc_nodes
      else
        find_nodes_loc(node, position, [])
      end
    end

    def find_comment(line:, column:)
      pos = buffer.loc_to_pos([line, column])

      comment = comments.bsearch do |comment|
        pos <= comment.loc.expression.end_pos
      end

      if comment
        if comment.loc.expression.begin_pos < pos
          comment
        end
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
          mapping.fetch(node_) << annot
        end

        Source.new(buffer: buffer, path: path, node: node_, mapping: mapping, comments: comments, ignores: ignores)
      else
        self
      end
    end

    def self.skip_arg_assertions(node)
      send_node, _ = deconstruct_sendish_and_block_nodes(node)
      return false unless send_node

      if send_node.type == :send
        receiver, method, args = deconstruct_send_node!(send_node)

        return false unless receiver

        if receiver.type == :const
          if type_name = module_name_from_node(receiver.children[0], receiver.children[1])
            if type_name.namespace.empty?
              if type_name.name == :Data && method == :define
                return true
              end
              if type_name.name == :Struct && method == :new
                return true
              end
            end
          end
        end
      end

      false
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
          when :return, :break, :next
            # Skip
          when :def, :defs
            # Skip
          when :kwargs
            # skip
          when :when
            # skip
          when :pair
            key, value = node.children
            key = insert_type_node(key, comments.except(last_line))
            value = insert_type_node(value, comments)
            node = node.updated(nil, [key, value])
            return adjust_location(node)
          when :masgn
            lhs, rhs = node.children
            node = node.updated(nil, [lhs, insert_type_node(rhs, comments)])
            return adjust_location(node)
          when :begin
            location = node.loc #: Parser::Source::Map & Parser::AST::_Collection
            if location.begin
              # paren
              child_assertions = comments.except(last_line)
              node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }
              node = adjust_location(node)
              return assertion_node(node, last_comment)
            end
          else
            if (receiver, name, * = deconstruct_send_node(node))
              if receiver.nil?
                if name == :attr_reader || name == :attr_writer || name == :attr_accessor
                  child_assertions = comments.except(last_line)
                  node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }
                  return adjust_location(node)
                end
              end
            end
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
                  *children.map do |child|
                    if child
                      insert_type_node(child, child_assertions)
                    end
                  end
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
      when :def
        name, args, body = node.children
        assertion_location = args&.location&.expression || (_ = node.location).name
        no_assertion_comments = comments.except(assertion_location.last_line)
        args = insert_type_node(args, no_assertion_comments)
        body = insert_type_node(body, comments) if body
        return adjust_location(node.updated(nil, [name, args, body]))
      when :defs
        object, name, args, body = node.children
        assertion_location = args&.location&.expression || (_ = node.location).name
        no_assertion_comments = comments.except(assertion_location.last_line)
        object = insert_type_node(object, no_assertion_comments)
        args = insert_type_node(args, no_assertion_comments)
        body = insert_type_node(body, comments) if body
        return adjust_location(node.updated(nil, [object, name, args, body]))
      else
        if skip_arg_assertions(node)
          # Data.define, Struct.new, ...??
          if node.location.expression
            first_line = node.location.expression.first_line
            last_line = node.location.expression.last_line

            child_assertions = comments.delete_if {|line, _ | first_line < line && line < last_line }
            node = map_child_node(node) {|child| insert_type_node(child, child_assertions) }

            return adjust_location(node)
          end
        end

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
        receiver_node, name, _, location = deconstruct_send_node!(send_node)

        if receiver_node
          if location.dot && location.selector
            location.selector.line
          end
        else
          location.selector.line
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
