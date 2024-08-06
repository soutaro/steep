module Steep
  class Typing
    class UnknownNodeError < StandardError
      attr_reader :op
      attr_reader :node

      def initialize(op, node:)
        @op = op
        @node = node
        super "Unknown node for #{op}: #{node.inspect}"
      end
    end

    class CursorContext
      attr_reader :index

      attr_reader :data

      def initialize(index)
        @index = index
      end

      def set(range, context = nil)
        if range.is_a?(CursorContext)
          range, context = range.data
          range or return
          context or return
        end

        context or raise
        return unless index

        if current_range = self.range
          if range.begin <= index && index <= range.end
            if current_range.begin <= range.begin && range.end <= current_range.end
              @data = [range, context]
            end
          end
        else
          @data = [range, context]
        end
      end

      def set_node_context(node, context)
        begin_pos = node.loc.expression.begin_pos
        end_pos = node.loc.expression.end_pos

        set(begin_pos..end_pos, context)
      end

      def set_body_context(node, context)
        case node.type
        when :class
          name_node, super_node, _ = node.children
          begin_pos = if super_node
                        super_node.loc.expression.end_pos
                      else
                        name_node.loc.expression.end_pos
                      end
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod

          set(begin_pos..end_pos, context)

        when :module
          name_node = node.children[0]
          begin_pos = name_node.loc.expression.end_pos
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
          set(begin_pos..end_pos, context)

        when :sclass
          name_node = node.children[0]
          begin_pos = name_node.loc.expression.end_pos
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
          set(begin_pos..end_pos, context)

        when :def, :defs
          if node.children.last
            args_node =
              case node.type
              when :def
                node.children[1]
              when :defs
                node.children[2]
              end

            body_begin_pos =
              case
              when node.loc.assignment # steep:ignore NoMethod
                # endless def
                node.loc.assignment.end_pos # steep:ignore NoMethod
              when args_node.loc.expression
                # with args
                args_node.loc.expression.end_pos
              else
                # without args
                node.loc.name.end_pos # steep:ignore NoMethod
              end

            body_end_pos =
              if node.loc.end # steep:ignore NoMethod
                node.loc.end.begin_pos # steep:ignore NoMethod
              else
                node.loc.expression.end_pos
              end

            set(body_begin_pos..body_end_pos, context)
          end

        when :block, :numblock
          range = block_range(node)
          set(range, context)

        when :for
          _, collection, _ = node.children

          begin_pos = collection.loc.expression.end_pos
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod

          set(begin_pos..end_pos, context)
        else
          raise "Unexpected node for insert_context: #{node.type}"
        end
      end

      def block_range(node)
        case node.type
        when :block
          send_node, args_node, _ = node.children
          begin_pos = if send_node.type != :lambda && args_node.loc.expression
                        args_node.loc.expression.end_pos
                      else
                        node.loc.begin.end_pos # steep:ignore NoMethod
                      end
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
        when :numblock
          send_node, _ = node.children
          begin_pos = node.loc.begin.end_pos # steep:ignore NoMethod
          end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
        end

        begin_pos..end_pos
      end

      def range
        range, _ = data
        range
      end

      def context
        _, context = data
        context
      end
    end

    attr_reader :source
    attr_reader :errors
    attr_reader :typing
    attr_reader :parent
    attr_reader :parent_last_update
    attr_reader :last_update
    attr_reader :should_update
    attr_reader :contexts
    attr_reader :root_context
    attr_reader :method_calls
    attr_reader :source_index
    attr_reader :cursor_context

    def initialize(source:, root_context:, parent: nil, parent_last_update: parent&.last_update, source_index: nil, cursor:)
      @source = source

      @parent = parent
      @parent_last_update = parent_last_update
      @last_update = parent&.last_update || 0
      @should_update = false

      @errors = []
      (@typing = {}).compare_by_identity
      @root_context = root_context
      (@method_calls = {}).compare_by_identity

      @cursor_context = CursorContext.new(cursor)
      if root_context
        cursor_context.set(0..source.buffer.content&.size || 0, root_context)
      end

      @source_index = source_index || Index::SourceIndex.new(source: source)
    end

    def add_error(error)
      errors << error
    end

    def add_typing(node, type, _context)
      typing[node] = type
      @last_update += 1

      type
    end

    def add_call(node, call)
      method_calls[node] = call

      call
    end

    def has_type?(node)
      typing.key?(node)
    end

    def type_of(node:)
      raise "`nil` given to `Typing#type_of(node:)`" unless node

      type = typing[node]

      if type
        type
      else
        if parent
          parent.type_of(node: node)
        else
          raise UnknownNodeError.new(:type, node: node)
        end
      end
    end

    def call_of(node:)
      call = method_calls[node]

      if call
        call
      else
        if parent
          parent.call_of(node: node)
        else
          raise UnknownNodeError.new(:call, node: node)
        end
      end
    end

    def block_range(node)
      case node.type
      when :block
        send_node, args_node, _ = node.children
        begin_pos = if send_node.type != :lambda && args_node.loc.expression
                      args_node.loc.expression.end_pos
                    else
                      node.loc.begin.end_pos # steep:ignore NoMethod
                    end
        end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
      when :numblock
        send_node, _ = node.children
        begin_pos = node.loc.begin.end_pos # steep:ignore NoMethod
        end_pos = node.loc.end.begin_pos # steep:ignore NoMethod
      end

      begin_pos..end_pos
    end

    def dump(io)
      # steep:ignore:start
      io.puts "Typing: "
      nodes.each_value do |node|
        io.puts "  #{Typing.summary(node)} => #{type_of(node: node).inspect}"
      end

      io.puts "Errors: "
      errors.each do |error|
        io.puts "  #{Typing.summary(error.node)} => #{error.inspect}"
      end
      # steep:ignore:end
    end

    def self.summary(node)
      src = node.loc.expression.source.split(/\n/).first
      line = node.loc.first_line
      col = node.loc.column

      "#{line}:#{col}:#{src}"
    end

    def new_child()
      child = self.class.new(
        source: source,
        parent: self,
        root_context: root_context,
        source_index: source_index.new_child,
        cursor: cursor_context.index
      )
      @should_update = true

      if block_given?
        yield child
      else
        child
      end
    end

    def each_typing(&block)
      typing.each(&block)
    end

    def save!
      raise "Unexpected save!" unless parent
      raise "Parent modified since #new_child: parent.last_update=#{parent.last_update}, parent_last_update=#{parent_last_update}" unless parent.last_update == parent_last_update

      each_typing do |node, type|
        parent.add_typing(node, type, nil)
      end

      parent.method_calls.merge!(method_calls)

      errors.each do |error|
        parent.add_error error
      end

      parent.cursor_context.set(cursor_context)

      parent.source_index.merge!(source_index)
    end
  end
end
