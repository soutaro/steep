module Steep
  module Services
    class SignatureHelpProvider
      MethodCall = TypeInference::MethodCall

      Item = _ = Struct.new(:method_type, :comment)

      attr_reader :source, :path, :subtyping, :typing, :buffer

      def env
        subtyping.factory.env
      end

      def initialize(source:, subtyping:)
        @source = source
        @subtyping = subtyping

        text =
          if source.node
            source.node.loc.expression.source
          end
        @buffer = RBS::Buffer.new(name: source.path, content: text || "")
      end

      def run(line:, column:)
        nodes = source.find_nodes(line: line, column: column)

        return unless nodes

        typing = type_check!(line: line, column: column)

        while true
          node = nodes.shift()
          parent = nodes.first

          node or return

          if node.type == :send
            pos = buffer.loc_to_pos([line, column])
            begin_loc = (_ = node.loc).begin #: Parser::Source::Range?
            end_loc = (_ = node.loc).end #: Parser::Source::Range?

            if begin_loc && end_loc
              if begin_loc.end_pos <= pos && pos <= end_loc.begin_pos
                # Given position is between open/close parens of args of send node

                if parent && (parent.type == :block || parent.type == :numblock)
                  send_node = parent.children[0]
                else
                  send_node = node
                end

                return signature_help_for(send_node, typing)
              end
            end
          end
        end
      end

      def type_check!(line:, column:)
        source = self.source.without_unrelated_defs(line: line, column: column)
        resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
        TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver)
      end

      def signature_help_for(node, typing)
        call = typing.call_of(node: node)
        context = typing.context_at(line: node.loc.expression.line, column: node.loc.expression.column)

        items = [] #: Array[Item]
        index = nil #: Integer?

        case call
        when MethodCall::Typed, MethodCall::Error
          type = call.receiver_type
          if type.is_a?(AST::Types::Self)
            type = context.self_type
          end

          shape = subtyping.builder.shape(
            type,
            public_only: !node.children[0].nil?,
            config: Interface::Builder::Config.new(self_type: type, class_type: nil, instance_type: nil, variable_bounds: {})
          )
          if shape
            if method = shape.methods[call.method_name]
              method.method_types.each.with_index do |method_type, i|
                defn = method_type.method_decls.to_a[0]&.method_def

                items << Item.new(subtyping.factory.method_type_1(method_type), defn&.comment)

                if call.is_a?(MethodCall::Typed)
                  if method_type.method_decls.intersect?(call.method_decls)
                    index = i
                  end
                end
              end
            end
          end
        when MethodCall::Untyped, MethodCall::NoMethodError
          return
        end

        [items, index]
      end
    end
  end
end
