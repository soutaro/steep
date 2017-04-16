module Steep
  class TypeConstruction
    attr_reader :assignability
    attr_reader :source
    attr_reader :env
    attr_reader :typing

    def initialize(assignability:, source:, env:, typing:)
      @assignability = assignability
      @source = source
      @env = env
      @typing = typing
    end

    def run(node)
      case node.type
      when :begin
        type = each_child_node(node).map do |child|
          run(child)
        end.last

        typing.add_typing(node, type)
      when :lvasgn
        name = node.children[0]
        lhs_type = env.lookup(name)
        rhs_type = run(node.children[1])

        if lhs_type
          unless assignability.test(src: rhs_type, dest: lhs_type)
            typing.add_error(Errors::IncompatibleAssignment.new(node: node, lhs_type: lhs_type, rhs_type: rhs_type))
          end
          typing.add_typing(node, lhs_type)
          env.add(name, lhs_type)
        else
          typing.add_typing(node, rhs_type)
          env.add(name, rhs_type)
        end

      when :lvar
        type = env.lookup(node.children[0]) || Types::Any.new
        typing.add_typing(node, type)

      when :str
        typing.add_typing(node, Types::Any.new)

      when :send
        recv_type = run(node.children[0])
        method_name = node.children[1]

        ret_type = assignability.method_type recv_type, method_name do |method_type|
          if method_type
            check_argument_types node, params: method_type.params, arguments: node.children.drop(2)
            method_type.return_type
          else
            # no method error
            typing.add_error Errors::NoMethod.new(node: node, method: method_name, type: recv_type)
          end
        end

        typing.add_typing(node, ret_type)

      when :int
        typing.add_typing(node, Types::Any.new)

      when :nil
        typing.add_typing(node, Types::Any.new)

      else
        p node

        typing.add_typing(node, Types::Any.new)
      end
    end

    def each_child_node(node)
      if block_given?
        node.children.each do |child|
          if child.is_a?(AST::Node)
            yield child
          end
        end
      else
        enum_for :each_child_node, node
      end
    end

    def check_argument_types(node, params:, arguments:)
      params.each_missing_argument arguments do |index|
        typing.add_error Errors::ExpectedArgumentMissing.new(node: node, index: index)
      end

      params.each_extra_argument arguments do |index|
        typing.add_error Errors::ExtraArgumentGiven.new(node: node, index: index)
      end

      arg_types = arguments.map do |arg|
        run arg
      end

      arguments.each.with_index do |arg_node, index|
        arg_type = arg_types[index]

        assignability.test_application(params: params, argument: arg_type, index: index) do |param_type|
          if param_type
            error = Errors::InvalidArgument.new(node: arg_node, expected: param_type, actual: arg_type)
            typing.add_error(error)
          end
        end
      end
    end

    def self.argument_typing_pairs(params:, arguments:)
      []
    end
  end
end
