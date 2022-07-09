module Steep
  module NodeHelper
    def each_child_node(node, &block)
      if block
        node.children.each do |child|
          if child.is_a?(Parser::AST::Node)
            yield child
          end
        end
      else
        enum_for :each_child_node, node
      end
    end

    def each_descendant_node(node, &block)
      if block
        each_child_node(node) do |child|
          yield child
          each_descendant_node(child, &block)
        end
      else
        enum_for :each_descendant_node, node
      end
    end

    def value_node?(node)
      case node.type
      when :true, :false, :str, :sym, :int, :float, :nil
        true
      when :lvar
        true
      when :const
        each_child_node(node).all? {|child| child.type == :cbase || value_node?(child) }
      when :array
        each_child_node(node).all? {|child| value_node?(child) }
      when :hash
        each_child_node(node).all? do |pair|
          each_child_node(pair).all? {|child| value_node?(child) }
        end
      when :dstr
        each_child_node(node).all? {|child| value_node?(child)}
      when :begin
        each_child_node(node).all? {|child| value_node?(node) }
      else
        false
      end
    end
  end
end
