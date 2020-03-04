module Steep
  class Typing
    Pair = Struct.new(:type, :context, keyword_init: true)

    class UnknownNodeError < StandardError
      attr_reader :op
      attr_reader :node

      def initialize(op, node:)
        @op = op
        @node = node
        super "Unknown node for #{op}: #{node.inspect}"
      end
    end

    attr_reader :errors
    attr_reader :parent
    attr_reader :parent_last_update
    attr_reader :last_update
    attr_reader :should_update
    attr_reader :pairs

    def initialize(parent: nil, parent_last_update: parent&.last_update)
      @parent = parent
      @parent_last_update = parent_last_update
      @last_update = parent&.last_update || 0
      @should_update = false

      @errors = []
      @pairs = {}.compare_by_identity
    end

    def add_error(error)
      errors << error
    end

    def add_pair(node, pair)
      pairs[node] = pair

      if should_update
        @last_update += 1
        @should_update = false
      end

      pair
    end

    def add_typing(node, type, context)
      add_pair(node, Pair.new(type: type, context: context))
    end

    def has_type?(node)
      pairs.key?(node)
    end

    def type_of(node:)
      type = pairs[node]&.type

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

    def context_of(node:)
      ctx = pairs[node]&.context

      if ctx
        ctx
      else
        if parent
          parent.context_of(node: node)
        else
          raise UnknownNodeError.new(:context, node: node)
        end
      end
    end

    def dump(io)
      io.puts "Typing: "
      pairs.each_key do |node|
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

    def new_child
      child = self.class.new(parent: self)
      @should_update = true

      if block_given?
        yield child
      else
        child
      end
    end

    def each_typing
      pairs.each do |node, pair|
        yield node, pair.type
      end
    end

    def each_pair(&block)
      pairs.each(&block)
    end

    def save!
      raise "Unexpected save!" unless parent
      raise "Parent modified since new_child" unless parent.last_update == parent_last_update

      each_pair do |node, pair|
        parent.add_pair(node, pair)
      end

      errors.each do |error|
        parent.add_error error
      end
    end
  end
end
