module Steep
  class Project
    class CompletionProvider
      Position = Struct.new(:line, :column, keyword_init: true) do
        def -(size)
          Position.new(line: line, column: column - size)
        end
      end
      Range = Struct.new(:start, :end, keyword_init: true)

      InstanceVariableItem = Struct.new(:identifier, :range, :type, keyword_init: true)
      LocalVariableItem = Struct.new(:identifier, :range, :type, keyword_init: true)
      MethodNameItem = Struct.new(:identifier, :range, :definition, :method_type, :inherited_method, keyword_init: true)

      attr_reader :source_text
      attr_reader :path
      attr_reader :subtyping
      attr_reader :modified_text
      attr_reader :source
      attr_reader :typing

      def initialize(source_text:, path:, subtyping:)
        @source_text = source_text
        @path = path
        @subtyping = subtyping
      end

      def type_check!(text)
        @modified_text = text

        Steep.measure "parsing" do
          @source = SourceFile.parse(text, path: path, factory: subtyping.factory)
        end

        Steep.measure "typechecking" do
          @typing = SourceFile.type_check(source, subtyping: subtyping)
        end
      end

      def run(line:, column:)
        source_text = self.source_text.dup
        index = index_for(source_text, line:line, column: column)
        possible_trigger = source_text[index-1]

        Steep.logger.debug "possible_trigger: #{possible_trigger.inspect}"

        position = Position.new(line: line, column: column)

        begin
          Steep.logger.tagged "completion_provider#run(line: #{line}, column: #{column})" do
            Steep.measure "type_check!" do
              type_check!(source_text)
            end
          end

          Steep.measure "completion item collection" do
            items_for_trigger(position: position)
          end

        rescue Parser::SyntaxError => exn
          Steep.logger.error "recovering syntax error: #{exn.inspect}"
          case possible_trigger
          when "."
            source_text[index-1] = " "
            type_check!(source_text)
            items_for_dot(position: position)
          when "@"
            source_text[index-1] = " "
            type_check!(source_text)
            items_for_atmark(position: position)
          else
            []
          end
        end
      end

      def range_from_loc(loc)
        Range.new(
          start: Position.new(line: loc.line, column: loc.column),
          end: Position.new(line: loc.last_line, column: loc.last_line)
        )
      end

      def at_end?(pos, of:)
        of.last_line == pos.line && of.last_column == pos.column
      end

      def range_for(position, prefix: "")
        if prefix.empty?
          Range.new(start: position, end: position)
        else
          Range.new(start: position - prefix.size, end: position)
        end
      end

      def items_for_trigger(position:)
        node, *parents = source.find_nodes(line: position.line, column: position.column)
        node ||= source.node

        return [] unless node

        items = []

        context = typing.context_at(line: position.line, column: position.column)

        case
        when node.type == :send && node.children[0] == nil && at_end?(position, of: node.loc.selector)
          # foo ←
          prefix = node.children[1].to_s

          method_items_for_receiver_type(context.self_type,
                                         include_private: true,
                                         prefix: prefix,
                                         position: position,
                                         items: items)
          local_variable_items_for_context(context, position: position, prefix: prefix, items: items)

        when node.type == :lvar && at_end?(position, of: node.loc)
          # foo ← (lvar)
          local_variable_items_for_context(context, position: position, prefix: node.children[0].name.to_s, items: items)

        when node.type == :send && node.children[0] && at_end?(position, of: node.loc.selector)
          # foo.ba ←
          receiver_type = case (type = typing.type_of(node: node.children[0]))
                          when AST::Types::Self
                            context.self_type
                          else
                            type
                          end
          prefix = node.children[1].to_s

          method_items_for_receiver_type(receiver_type,
                                         include_private: false,
                                         prefix: prefix,
                                         position: position,
                                         items: items)

        when node.type == :const && node.children[0] == nil && at_end?(position, of: node.loc)
          # Foo ← (const)
          prefix = node.children[1].to_s

          method_items_for_receiver_type(context.self_type,
                                         include_private: false,
                                         prefix: prefix,
                                         position: position,
                                         items: items)

        when node.type == :send && at_end?(position, of: node.loc.dot)
          # foo.← ba
          receiver_type = case (type = typing.type_of(node: node.children[0]))
                          when AST::Types::Self
                            context.self_type
                          else
                            type
                          end

          method_items_for_receiver_type(receiver_type,
                                         include_private: false,
                                         prefix: "",
                                         position: position,
                                         items: items)

        when node.type == :ivar && at_end?(position, of: node.loc)
          # @fo ←
          instance_variable_items_for_context(context, position: position, prefix: node.children[0].to_s, items: items)

        else
          method_items_for_receiver_type(context.self_type,
                                         include_private: true,
                                         prefix: "",
                                         position: position,
                                         items: items)
          local_variable_items_for_context(context, position: position, prefix: "", items: items)
          instance_variable_items_for_context(context, position: position, prefix: "", items: items)
        end

        items
      end

      def items_for_dot(position:)
        # foo. ←
        shift_pos = position-1
        node, *parents = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
        node ||= source.node

        return [] unless node

        if at_end?(shift_pos, of: node.loc)
          context = typing.context_at(line: position.line, column: position.column)
          receiver_type = case (type = typing.type_of(node: node))
                          when AST::Types::Self
                            context.self_type
                          else
                            type
                          end

          items = []
          method_items_for_receiver_type(receiver_type,
                                         include_private: false,
                                         prefix: "",
                                         position: position,
                                         items: items)
          items
        else
          []
        end
      end

      def items_for_atmark(position:)
        # @ ←
        shift_pos = position-1
        node, *parents = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
        node ||= source.node

        return [] unless node

        context = typing.context_at(line: position.line, column: position.column)
        items = []
        instance_variable_items_for_context(context, prefix: "", position: position, items: items)
        items
      end

      def method_items_for_receiver_type(type, include_private:, prefix:, position:, items:)
        range = range_for(position, prefix: prefix)
        definition = case type
                     when AST::Types::Name::Instance
                       type_name = subtyping.factory.type_name_1(type.name)
                       subtyping.factory.definition_builder.build_instance(type_name)
                     when AST::Types::Name::Class, AST::Types::Name::Module
                       type_name = subtyping.factory.type_name_1(type.name)
                       subtyping.factory.definition_builder.build_singleton(type_name)
                     when AST::Types::Name::Interface
                       type_name = subtyping.factory.type_name_1(type.name)
                       interface = subtyping.factory.env.find_class(type_name)
                       subtyping.factory.definition_builder.build_interface(type_name, interface)
                     end

        if definition
          definition.methods.each do |name, method|
            if include_private || method.public?
              if name.to_s.start_with?(prefix)
                if word_name?(name.to_s)
                  method.method_types.each do |method_type|
                    next if disallowed_method?(name)
                    items << MethodNameItem.new(identifier: name,
                                                range: range,
                                                definition: method,
                                                method_type: method_type,
                                                inherited_method: inherited_method?(method, type))
                  end
                end
              end
            end
          end
        end
      end

      def word_name?(name)
        name =~ /\w/
      end

      def local_variable_items_for_context(context, position:, prefix:, items:)
        range = range_for(position, prefix: prefix)
        context.lvar_env.each do |name, type|
          if name.to_s.start_with?(prefix)
            items << LocalVariableItem.new(identifier: name,
                                           range: range,
                                           type: type)
          end
        end
      end

      def instance_variable_items_for_context(context, position:, prefix:, items:)
        range = range_for(position, prefix: prefix)
        context.type_env.ivar_types.map do |name, type|
          if name.to_s.start_with?(prefix)
            items << InstanceVariableItem.new(identifier: name,
                                              range: range,
                                              type: type)
          end
        end
      end

      def index_for(string, line:, column:)
        index = 0

        string.each_line.with_index do |s, i|
          if i+1 == line
            index += column
            break
          else
            index += s.size
          end
        end

        index
      end

      def inherited_method?(method, type)
        method.implemented_in&.name&.name != type.name&.name
      end

      def disallowed_method?(name)
        # initialize isn't invoked by developers when creating
        # instances of new classes, so don't show it as
        # an LSP option
        name == :initialize
      end
    end
  end
end
