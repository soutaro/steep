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

    def initialize(source:, root_context:, parent: nil, parent_last_update: parent&.last_update, contexts: nil, source_index: nil)
      @source = source

      @parent = parent
      @parent_last_update = parent_last_update
      @last_update = parent&.last_update || 0
      @should_update = false

      @errors = []
      (@typing = {}).compare_by_identity
      @root_context = root_context
      @contexts = contexts || TypeInference::ContextArray.from_source(source: source, context: root_context)
      (@method_calls = {}).compare_by_identity

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

    def add_context(range, context:)
      contexts.insert_context(range, context: context)
      @last_update += 1
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

    def add_context_for_node(node, context:)
      begin_pos = node.loc.expression.begin_pos
      end_pos = node.loc.expression.end_pos

      add_context(begin_pos..end_pos, context: context)
    end

    def block_range(node)
      case node.type
      when :block
        send_node, args_node, _ = node.children
        begin_pos = if send_node.type != :lambda && args_node.loc.expression
                      args_node.loc.expression.end_pos
                    else
                      node.loc.begin.end_pos
                    end
        end_pos = node.loc.end.begin_pos
      when :numblock
        send_node, _ = node.children
        begin_pos = node.loc.begin.end_pos
        end_pos = node.loc.end.begin_pos
      end

      begin_pos..end_pos
    end

    def add_context_for_body(node, context:)
      case node.type
      when :class
        name_node, super_node, _ = node.children
        begin_pos = if super_node
                      super_node.loc.expression.end_pos
                    else
                      name_node.loc.expression.end_pos
                    end
        end_pos = node.loc.end.begin_pos

        add_context(begin_pos..end_pos, context: context)

      when :module
        name_node = node.children[0]
        begin_pos = name_node.loc.expression.end_pos
        end_pos = node.loc.end.begin_pos
        add_context(begin_pos..end_pos, context: context)

      when :sclass
        name_node = node.children[0]
        begin_pos = name_node.loc.expression.end_pos
        end_pos = node.loc.end.begin_pos
        add_context(begin_pos..end_pos, context: context)

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
            when node.loc.assignment
              # endless def
              node.loc.assignment.end_pos
            when args_node.loc.expression
              # with args
              args_node.loc.expression.end_pos
            else
              # without args
              node.loc.name.end_pos
            end

          body_end_pos =
            if node.loc.end
              node.loc.end.begin_pos
            else
              node.loc.expression.end_pos
            end

          add_context(body_begin_pos..body_end_pos, context: context)
        end

      when :block, :numblock
        range = block_range(node)
        add_context(range, context: context)

      when :for
        _, collection, _ = node.children

        begin_pos = collection.loc.expression.end_pos
        end_pos = node.loc.end.begin_pos

        add_context(begin_pos..end_pos, context: context)
      else
        raise "Unexpected node for insert_context: #{node.type}"
      end
    end

    def context_at(line:, column:)
      contexts.at(line: line, column: column) ||
        (parent ? parent.context_at(line: line, column: column) : root_context)
    end

    def dump(io)
      io.puts "Typing: "
      nodes.each_value do |node|
        io.puts "  #{Typing.summary(node)} => #{type_of(node: node).inspect}"
      end

      io.puts "Errors: "
      errors.each do |error|
        io.puts "  #{Typing.summary(error.node)} => #{error.inspect}"
      end
    end

    def self.summary(node)
      src = node.loc.expression.source.split(/\n/).first
      line = node.loc.first_line
      col = node.loc.column

      "#{line}:#{col}:#{src}"
    end

    def new_child(range)
      context = contexts[range.begin] || contexts.root.context
      child = self.class.new(source: source,
                             parent: self,
                             root_context: root_context,
                             contexts: TypeInference::ContextArray.new(buffer: contexts.buffer, range: range, context: context),
                             source_index: source_index.new_child)
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

      parent.contexts.merge(contexts)

      parent.method_calls.merge!(method_calls)

      errors.each do |error|
        parent.add_error error
      end

      parent.source_index.merge!(source_index)
    end
  end
end
