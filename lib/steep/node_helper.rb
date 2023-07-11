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
      when :self
        true
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
        each_child_node(node).all? {|child| value_node?(child) }
      else
        false
      end
    end

    def deconstruct_if_node(node)
      if node.type == :if
        [
          node.children[0],
          node.children[1],
          node.children[2],
          _ = node.location
        ]
      end
    end

    def deconstruct_if_node!(node)
      deconstruct_if_node(node) or raise
    end

    def test_if_node(node)
      if (a, b, c, d = deconstruct_if_node(node))
        yield(a, b, c, d)
      else
        false
      end
    end

    def deconstruct_whileish_node(node)
      case node.type
      when :while, :until, :while_post, :until_post
        [
          node.children[0],
          node.children[1],
          _ = node.location
        ]
      end
    end

    def deconstruct_whileish_node!(node)
      deconstruct_whileish_node(node) or raise
    end

    def test_whileish_node(node)
      if (a, b, c = deconstruct_whileish_node(node))
        yield(a, b, c)
      else
        false
      end
    end

    def deconstruct_case_node(node)
      case node.type
      when :case
        cond, *whens, else_ = node.children
        [
          cond,
          whens,
          else_,
          _ = node.loc
        ]
      end
    end

    def deconstruct_case_node!(node)
      deconstruct_case_node(node) or raise
    end

    def test_case_node(node)
      if (a, b, c, d = deconstruct_case_node(node))
        yield a, b, c, d
      else
        false
      end
    end

    def deconstruct_when_node(node)
      case node.type
      when :when
        *conds, body = node.children
        [
          conds,
          body,
          _ = node.loc
        ]
      end
    end

    def deconstruct_when_node!(node)
      deconstruct_when_node(node) or raise
    end

    def test_when_node(node)
      if (a, b, c = deconstruct_when_node(node))
        yield a, b, c
      else
        false
      end
    end

    def deconstruct_rescue_node(node)
      case node.type
      when :rescue
        body, *resbodies, else_ = node.children

        [
          body,
          resbodies,
          else_,
          _ = node.loc
        ]
      end
    end

    def deconstruct_rescue_node!(node)
      deconstruct_rescue_node(node) or raise
    end

    def test_rescue_node(node)
      if (a, b, c, d = deconstruct_rescue_node(node))
        yield a, b, c, d
      else
        false
      end
    end

    def deconstruct_resbody_node(node)
      case node.type
      when :resbody
        [
          node.children[0],
          node.children[1],
          node.children[2],
          _  = node.loc
        ]
      end
    end

    def deconstruct_resbody_node!(node)
      deconstruct_resbody_node(node) or raise
    end

    def test_resbody_node(node)
      if (a, b, c, d = deconstruct_resbody_node(node))
        yield a, b, c, d
      else
        false
      end
    end

    def deconstruct_send_node(node)
      case node.type
      when :send, :csend
        receiver, selector, *args = node.children
        [
          receiver,
          selector,
          args,
          _  = node.loc
        ]
      end
    end

    def deconstruct_send_node!(node)
      deconstruct_send_node(node) or raise
    end

    def test_send_node(node)
      if (a, b, c, d = deconstruct_send_node(node))
        yield a, b, c, d
      else
        false
      end
    end

    def deconstruct_sendish_and_block_nodes(*nodes)
      send_node, block_node = nodes.take(2)

      if send_node
        case send_node.type
        when :send, :csend, :super
          if block_node
            case block_node.type
            when :block, :numblock
              if send_node.equal?(block_node.children[0])
                return [send_node, block_node]
              end
            end
          end

          [send_node, nil]
        when :zsuper
          # zsuper doesn't receive block
          [send_node, nil]
        end
      end
    end
  end
end
