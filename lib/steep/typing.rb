module Steep
  class Typing
    attr_reader :errors
    attr_reader :typing
    attr_reader :nodes
    attr_reader :var_typing
    attr_reader :parent

    def initialize(parent: nil)
      @parent = parent

      @errors = []
      @nodes = {}
      @var_typing = {}
      @typing = {}
    end

    def add_error(error)
      errors << error
    end

    def add_typing(node, type)
      typing[node.__id__] = type
      nodes[node.__id__] = node

      type
    end

    def has_type?(node)
      typing.key?(node.__id__)
    end

    def type_of(node:)
      type = typing[node.__id__]

      if type
        type
      else
        if parent
          parent.type_of(node: node)
        else
          raise "Unknown node for typing: #{node.inspect}"
        end
      end
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

    def new_child
      yield self.class.new(parent: self)
    end

    def each_typing
      nodes.each do |id, node|
        yield node, typing[id]
      end
    end

    def save!
      raise "Unexpected save!" unless parent

      each_typing do |node, type|
        parent.add_typing(node, type)
      end

      errors.each do |error|
        parent.add_error error
      end
    end
  end
end
