module Steep
  module Services
    class CodeActionProvider
      Action = Data.define(:edit_range, :new_texts)
      EditRange = Data.define(:start, :end)
      EditPosition = Data.define(:line, :character)

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
                      .parse(text, path:, factory: subtyping.factory)
                      .without_unrelated_defs(line:, column:)
        end

        Steep.measure "typechecking" do
          location = source.buffer.loc_to_pos([line, column])
          resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
          @typing = TypeCheckService.type_check(source:, subtyping:, constant_resolver: resolver, cursor: location)
        end
      end

      def run(range:)
        return unless defined?(DidYouMean)

        Steep.logger.tagged "CodeActionProvider#run" do
          Steep.measure "type_check!" do
            type_check!(source_text, line: range[:start][:line]+1, column: range[:start][:character])
          end
        end

        Steep.measure "code action item collection" do
          action_for(range:)
        end
      end

      def action_for(range:)
        node, *parents = source.find_nodes(line: range[:start][:line]+1, column: range[:start][:character])
        node ||= source.node

        return unless node && parents

        dictionary = [] #: Array[Symbol]

        context = typing.cursor_context.context or raise

        case node.type
        when :send
          include_private = false
          receiver_type =
            if node.children[0] == nil
              # foo
              include_private = true
              context.self_type
            else
              # foo.bar
              typing.type_of(node: node.children[0])
            end

          mistype_name = node.children[1]
          method_items_for_receiver_type(receiver_type, include_private:, position: range[:start], dictionary:)
          edit_range = EditRange.new(
            start: EditPosition.new(line: range[:start][:line], character: range[:start][:character]),
            end: EditPosition.new(line: range[:end][:line], character: range[:end][:character])
          )
        when :self
          # self&.foo
          receiver_type = context.self_type
          mistype_node = parents[0] or raise
          mistype_name = mistype_node.children[1]
          method_items_for_receiver_type(receiver_type, include_private: false, position: range[:start], dictionary:)
          edit_range = EditRange.new(
            start: EditPosition.new(line: mistype_node.loc.selector.line-1, character: mistype_node.loc.selector.column), # steep:ignore
            end: EditPosition.new(line: mistype_node.loc.selector.last_line-1, character: mistype_node.loc.selector.last_column) # steep:ignore
          )
        when :csend
          # foo&.bar
          receiver_type = typing.type_of(node: node.children[0])
          mistype_name = node.children[1]
          method_items_for_receiver_type(receiver_type, include_private: false, position: range[:start], dictionary:)
          edit_range = EditRange.new(
            start: EditPosition.new(line: node.loc.selector.line-1, character: node.loc.selector.column), # steep:ignore
            end: EditPosition.new(line: node.loc.selector.last_line-1, character: node.loc.selector.last_column) # steep:ignore
          )
        end
        return unless mistype_name
        return unless edit_range

        new_texts = DidYouMean::SpellChecker.new(dictionary:).correct(mistype_name)
        new_texts.map!(&:to_s)

        Action.new(
          edit_range: edit_range,
          new_texts: new_texts
        )
      end

      def method_items_for_receiver_type(type, include_private:, position:, dictionary:)
        context = typing.cursor_context.context or raise

        config =
          if (module_type = context.module_context&.module_type) && (instance_type = context.module_context&.instance_type)
            Interface::Builder::Config.new(
              self_type: context.self_type,
              class_type: module_type,
              instance_type: instance_type,
              variable_bounds: context.variable_context.upper_bounds
            )
          else
            Interface::Builder::Config.new(self_type: context.self_type, variable_bounds: context.variable_context.upper_bounds)
          end

        if shape = subtyping.builder.shape(type, config)
          shape = shape.public_shape unless include_private

          shape.methods.methods.each do |key, _entry|
            dictionary << key
          end
        end
      end
    end
  end
end
