module Steep
  class Typing
    attr_reader :errors
    attr_reader :typing
    attr_reader :nodes
    attr_reader :var_typing

    def initialize
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

    def add_var_type(variable, type)
      if var_typing.key?(variable)
        unless var_typing[variable] == type
          raise "Unexpected variable typing: existing=#{var_typing[variable]}, new=#{type}"
        end
      end

      var_typing[variable] = type
    end

    def type_of(node:)
      typing[node.__id__] or raise "Unknown node for typing: #{node.inspect}"
    end

    def type_of_variable(name: nil, label: nil)
      var_typing.each do |var, type|
        if (!name || var.name == name) && (!label || var.label == label)
          return type
        end
      end

      raise "Unknown variable for typing: #{name}@#{label}"
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
  end
end
