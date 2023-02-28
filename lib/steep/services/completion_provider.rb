module Steep
  module Services
    class CompletionProvider
      Position = _ = Struct.new(:line, :column, keyword_init: true) do
        # @implements Position
        def -(size)
          Position.new(line: line, column: column - size)
        end
      end

      Range = _ = Struct.new(:start, :end, keyword_init: true)

      InstanceVariableItem = _ = Struct.new(:identifier, :range, :type, keyword_init: true)
      LocalVariableItem = _ = Struct.new(:identifier, :range, :type, keyword_init: true)
      ConstantItem = _ = Struct.new(:env, :identifier, :range, :type, :full_name, keyword_init: true) do
        # @implements ConstantItem

        def class?
          env.class_entry(full_name) ? true : false
        end

        def module?
          env.module_entry(full_name) ? true : false
        end

        def comments
          case entry = env.constant_entry(full_name)
          when RBS::Environment::ConstantEntry
            [entry.decl.comment].compact
          when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
            entry.decls.filter_map {|d| d.decl.comment }
          when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
            [entry.decl.comment].compact
          else
            raise
          end
        end
      end
      MethodNameItem = _ = Struct.new(:identifier, :range, :receiver_type, :method_type, :method_decls, keyword_init: true) do
        # @implements MethodNameItem

        def comment
          case method_decls.size
          when 0
            nil
          when 1
            method = method_decls.to_a.first or raise
            method.method_def&.comment
          else
            nil
          end
        end

        def inherited?
          case receiver_type = receiver_type()
          when AST::Types::Name::Instance, AST::Types::Name::Singleton, AST::Types::Name::Interface
            method_decls.any? do |decl|
              decl.method_name.type_name != receiver_type.name
            end
          else
            false
          end
        end
      end

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

      def type_check!(text, line:, column:)
        @modified_text = text

        Steep.measure "parsing" do
          @source = Source
                      .parse(text, path: path, factory: subtyping.factory)
                      .without_unrelated_defs(line: line, column: column)
        end

        Steep.measure "typechecking" do
          resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
          @typing = TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver)
        end
      end

      def env
        subtyping.factory.env
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
              type_check!(source_text, line: line, column: column)
            end
          end

          Steep.measure "completion item collection" do
            items_for_trigger(position: position)
          end

        rescue Parser::SyntaxError => exn
          Steep.logger.info "recovering syntax error: #{exn.inspect}"
          case possible_trigger
          when "."
            source_text[index-1] = " "
            type_check!(source_text, line: line, column: column)
            items_for_dot(position: position)
          when "@"
            source_text[index-1] = " "
            type_check!(source_text, line: line, column: column)
            items_for_atmark(position: position)
          when ":"
            if source_text[index-2] == ":"
              source_text[index-1] = " "
              source_text[index-2] = " "
              type_check!(source_text, line: line, column: column)
              items_for_colon2(position: position)
            else
              []
            end
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
        if of
          of.last_line == pos.line && of.last_column == pos.column
        end
      end

      def range_for(position, prefix: "")
        if prefix.empty?
          Range.new(start: position, end: position)
        else
          Range.new(start: position - prefix.size, end: position)
        end
      end

      def items_for_trigger(position:)
        node, *_parents = source.find_nodes(line: position.line, column: position.column)
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
          local_variable_items_for_context(context, position: position, prefix: node.children[0].to_s, items: items)

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
          constant_items_for_context(context, prefix: prefix, position: position, items: items)

        when node.type == :const && node.children[0] && at_end?(position, of: node.loc)
          # Foo::Ba ← (const)
          parent_node = node.children[0]
          parent_type = typing.type_of(node: parent_node)

          if parent_type
            prefix = node.children[1].to_s

            method_items_for_receiver_type(parent_type,
                                           include_private: false,
                                           prefix: prefix,
                                           position: position,
                                           items: items)
            constant_items_for_context(context, parent: parent_node, prefix: prefix, position: position, items: items)
          end

        when node.type == :send && at_end?(position, of: node.loc.dot) && node.loc.dot.source == "."
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

        when node.type == :send && at_end?(position, of: node.loc.dot) && node.loc.dot.source == "::"
          # foo::← ba
          items.push(*items_for_colon2(position: position))

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
          constant_items_for_context(context, position: position, prefix: "", items: items)
        end

        items
      end

      def items_for_dot(position:)
        # foo. ←
        shift_pos = position-1
        node, *_parents = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
        node ||= source.node

        return [] unless node

        if at_end?(shift_pos, of: node.loc)
          begin
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
          rescue Typing::UnknownNodeError
            []
          end
        else
          []
        end
      end

      def items_for_colon2(position:)
        # :: ←
        shift_pos = position-2
        node, *_ = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
        node ||= source.node

        items = []
        case node&.type
        when :const
          # Constant:: ←
          context = typing.context_at(line: position.line, column: position.column)
          constant_items_for_context(context, parent: node, position: position, items: items, prefix: "")
        when nil
          # :: ←
          context = typing.context_at(line: position.line, column: position.column)
          constant_items_for_context(context, parent: nil, position: position, items: items, prefix: "")
        end

        if node
          items.push(*items_for_dot(position: position - 1))
        end

        items
      end

      def items_for_atmark(position:)
        # @ ←
        shift_pos = position-1
        node, *_ = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
        node ||= source.node

        return [] unless node

        context = typing.context_at(line: position.line, column: position.column)
        items = []
        instance_variable_items_for_context(context, prefix: "@", position: position, items: items)
        items
      end

      def method_items_for_receiver_type(type, include_private:, prefix:, position:, items:)
        range = range_for(position, prefix: prefix)
        context = typing.context_at(line: position.line, column: position.column)

        shape = subtyping.builder.shape(
          type,
          public_only: !include_private,
          config: Interface::Builder::Config.new(
            self_type: context.self_type,
            class_type: context.module_context&.module_type,
            instance_type: context.module_context&.instance_type,
            variable_bounds: context.variable_context.upper_bounds
          )
        )
        # factory.shape(type, self_type: type, private: include_private)

        shape.methods.each do |name, method_entry|
          next if disallowed_method?(name)

          if name.to_s.start_with?(prefix)
            if word_name?(name.to_s)
              method_entry.method_types.each do |method_type|
                items << MethodNameItem.new(
                  identifier: name,
                  range: range,
                  receiver_type: type,
                  method_type: subtyping.factory.method_type_1(method_type),
                  method_decls: method_type.method_decls
                )
              end
            end
          end
        end
      rescue RuntimeError => _exn
        # nop
      end

      def word_name?(name)
        name =~ /\w/
      end

      def local_variable_items_for_context(context, position:, prefix:, items:)
        range = range_for(position, prefix: prefix)
        context.type_env.local_variable_types.each do |name, pair|
          type, _ = pair

          if name.to_s.start_with?(prefix)
            items << LocalVariableItem.new(identifier: name, range: range, type: type)
          end
        end
      end

      def constant_items_for_context(context, parent: nil, position:, prefix:, items:)
        range = range_for(position, prefix: prefix)

        if parent
          case parent.type
          when :const
            const_name = typing.source_index.reference(constant_node: parent)
            consts = context.type_env.constant_env.children(const_name)
          end
        else
          consts = context.type_env.constant_env.constants
        end

        if consts
          consts.each do |name, tuple|
            type, full_name, _ = tuple

            if name.to_s.start_with?(prefix)
              items << ConstantItem.new(env: env, identifier: name, range: range, type: type, full_name: full_name)
            end
          end
        end
      end

      def instance_variable_items_for_context(context, position:, prefix:, items:)
        range = range_for(position, prefix: prefix)
        context.type_env.instance_variable_types.each do |name, type|
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

      def disallowed_method?(name)
        # initialize isn't invoked by developers when creating
        # instances of new classes, so don't show it as
        # an LSP option
        name == :initialize
      end
    end
  end
end
