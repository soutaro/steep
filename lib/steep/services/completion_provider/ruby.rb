module Steep
  module Services
    module CompletionProvider
      class Ruby
        include NodeHelper

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
            location = source.buffer.loc_to_pos([line, column])
            resolver = ::RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
            @typing = TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver, cursor: location)
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

            @source_text = source_text.dup

            case possible_trigger
            when "."
              if source_text[index-2] == "&"
                source_text[index-1] = " "
                source_text[index-2] = " "
                type_check!(source_text, line: line, column: column)
                items_for_qcall(position: position)
              else
                source_text[index-1] = " "
                type_check!(source_text, line: line, column: column)
                items_for_dot(position: position)
              end
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
              items = [] #: Array[item]
              items_for_following_keyword_arguments(source_text, index: index, line: line, column: column, items: items)
              items
            end
          end
        end

        def run_at_comment(line:, column:)
          source_text = self.source_text.dup
          index = index_for(source_text, line:line, column: column)
          possible_trigger = source_text[index-1]

          Steep.logger.debug "possible_trigger: #{possible_trigger.inspect}"

          position = Position.new(line: line, column: column)

          begin
            Steep.logger.tagged "completion_provider#run(line: #{line}, column: #{column})" do
              Steep.measure "type_check!" do
                type_check!(source_text, line: line, column: column)
              rescue Parser::SyntaxError
                return
              end
            end

            locator = Locator::Ruby.new(source)
            case result = locator.find(line, column)
            when Locator::CommentResult
              buffer = typing.source.buffer

              items = [] #: Array[item]

              prefix_size, rbs_items = items_for_rbs(position: position, buffer: buffer)
              items.concat rbs_items

              comment_content = result.comment.text[1..] #: String

              range = Range.new(
                start: Position.new(line: line, column: column),
                end: Position.new(line: line, column: column)
              )

              annotation_items = [
                TextItem.new(label: "steep:ignore:start", text: "steep:ignore:start", help_text: "Open ignore block", range: range),
                TextItem.new(label: "steep:ignore:end", text: "steep:ignore:end", help_text: "Close ignore block", range: range),
                TextItem.new(label: "steep:ignore", text: "steep:ignore ${1:optional diagnostics}", help_text: "Ignore line", range: range),
                TextItem.new(label: "@type var x: T", text: "@type var ${1:variable}: ${2:var type}", help_text: "Type of local variable", range: range),
                TextItem.new(label: "@type self: T", text: "@type self: ${1:self type}", help_text: "Type of `self`", range: range),
                TextItem.new(label: "@type block: T", text: "@type block: ${1:block type}", help_text: "Type of `block`", range: range),
                TextItem.new(label: "@type break: T", text: "@type break: ${1:break type}", help_text: "Type of `block`", range: range),
              ]

              annotation_items.each do |item|
                if item.text.start_with?(comment_content)
                  items << TextItem.new(
                    label: item.label,
                    text: item.text,
                    help_text: item.help_text,
                    range: Range.new(
                      start: Position.new(line: item.range.start.line, column: item.range.start.column - comment_content.size),
                      end: item.range.end
                    )
                  )
                end
              end

              [prefix_size, items]
            when Locator::TypeApplicationResult, Locator::TypeAssertionResult, Locator::AnnotationResult
              buffer = typing.source.buffer
              items_for_rbs(position: position, buffer: buffer)
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

        def at_comment?(position)
          source.find_comment(line: position.line, column: position.column)
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

          return [] unless node && parents

          items = [] #: Array[item]

          context = typing.cursor_context.context or raise

          case
          when node.type == :send && node.children[0] == nil && at_end?(position, of: (_ = node.loc).selector)
            # foo ←
            prefix = node.children[1].to_s

            method_items_for_receiver_type(context.self_type, include_private: true, prefix: prefix, position: position, items: items)
            local_variable_items_for_context(context, position: position, prefix: prefix, items: items)

            if (send_node, block_node = deconstruct_sendish_and_block_nodes(*parents))
              keyword_argument_items_for_method(
                call_node: block_node || send_node,
                send_node: send_node,
                position: position,
                prefix: prefix,
                items: items
              )
            end

          when node.type == :lvar && at_end?(position, of: node.loc)
            # foo ← (lvar)
            local_variable_items_for_context(context, position: position, prefix: node.children[0].to_s, items: items)

          when node.type == :send && node.children[0] && at_end?(position, of: (_ = node.loc).selector)
            # foo.ba ←
            receiver_type =
              case (type = typing.type_of(node: node.children[0]))
              when AST::Types::Self
                context.self_type
              else
                type
              end
            prefix = node.children[1].to_s

            method_items_for_receiver_type(receiver_type, include_private: false, prefix: prefix, position: position, items: items)

          when node.type == :csend && node.children[0] && at_end?(position, of: (_ = node.loc).selector)
            # foo&.ba ←
            receiver_type =
              case (type = typing.type_of(node: node.children[0]))
              when AST::Types::Self
                context.self_type
              else
                unwrap_optional(type)
              end
            prefix = node.children[1].to_s

            method_items_for_receiver_type(receiver_type, include_private: false, prefix: prefix, position: position, items: items)

          when node.type == :const && node.children[0] == nil && at_end?(position, of: node.loc)
            # Foo ← (const)
            prefix = node.children[1].to_s

            method_items_for_receiver_type(context.self_type, include_private: false, prefix: prefix, position: position, items: items)
            constant_items_for_context(context, prefix: prefix, position: position, items: items)

          when node.type == :const && node.children[0] && at_end?(position, of: node.loc)
            # Foo::Ba ← (const)
            parent_node = node.children[0]
            parent_type = typing.type_of(node: parent_node)

            if parent_type
              prefix = node.children[1].to_s

              method_items_for_receiver_type(parent_type, include_private: false, prefix: prefix, position: position, items: items)
              constant_items_for_context(context, parent: parent_node, prefix: prefix, position: position, items: items)
            end

          when node.type == :send && at_end?(position, of: (_ = node.loc).dot) && (_ = node.loc).dot.source == "."
            # foo.← ba
            receiver_type =
              case (type = typing.type_of(node: node.children[0]))
              when AST::Types::Self
                context.self_type
              else
                type
              end

            method_items_for_receiver_type(receiver_type, include_private: false, prefix: "", position: position, items: items)

          when node.type == :send && at_end?(position, of: (_ = node.loc).dot) && (_ = node.loc).dot.source == "::"
            # foo::← ba
            items.push(*items_for_colon2(position: position))

          when node.type == :csend && at_end?(position, of: (_ = node.loc).dot)
            # foo&.← ba
            receiver_type =
              case (type = typing.type_of(node: node.children[0]))
              when AST::Types::Self
                context.self_type
              else
                unwrap_optional(type)
              end

            method_items_for_receiver_type(receiver_type, include_private: false, prefix: "", position: position, items: items)

          when node.type == :ivar && at_end?(position, of: node.loc)
            # @fo ←
            instance_variable_items_for_context(context, position: position, prefix: node.children[0].to_s, items: items)

          else
            method_items_for_receiver_type(context.self_type, include_private: true, prefix: "", position: position, items: items)
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
              context = typing.cursor_context.context or raise
              receiver_type =
                case (type = typing.type_of(node: node))
                when AST::Types::Self
                  context.self_type
                else
                  type
                end

              items = [] #: Array[item]
              method_items_for_receiver_type(receiver_type, include_private: false, prefix: "", position: position, items: items)
              items
            rescue Typing::UnknownNodeError
              []
            end
          else
            []
          end
        end

        def items_for_qcall(position:)
          # foo&. ←
          shift_pos = position-2
          node, *_parents = source.find_nodes(line: shift_pos.line, column: shift_pos.column)
          node ||= source.node

          return [] unless node

          if at_end?(shift_pos, of: node.loc)
            begin
              context = typing.cursor_context.context or raise
              receiver_type =
                case (type = typing.type_of(node: node))
                when AST::Types::Self
                  context.self_type
                else
                  unwrap_optional(type)
                end

              items = [] #: Array[item]
              method_items_for_receiver_type(receiver_type, include_private: false, prefix: "", position: position, items: items)
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

          items = [] #: Array[item]
          case node&.type
          when :const
            # Constant:: ←
            context = typing.cursor_context.context or raise
            constant_items_for_context(context, parent: node, position: position, items: items, prefix: "")
          when nil
            # :: ←
            context = typing.cursor_context.context or raise
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

          context = typing.cursor_context.context or raise
          items = [] #: Array[item]
          instance_variable_items_for_context(context, prefix: "@", position: position, items: items)
          items
        end

        def items_for_rbs(position:, buffer:)
          items = [] #: Array[item]

          context = typing.cursor_context.context or raise
          completion = TypeName.new(env: context.env, context: context.module_context.nesting, dirs: [])
          prefix = TypeName::Prefix.parse(buffer, line: position.line, column: position.column)

          size = prefix&.size || 0
          range = Range.new(start: position - size, end: position)

          completion.find_type_names(prefix).each do |name|
            if (absolute, relative = completion.resolve_name_in_context(name))
              items << TypeNameItem.new(relative_type_name: relative, absolute_type_name: absolute, env: context.env, range: range)
            end
          end

          [size, items]
        end

        def items_for_following_keyword_arguments(text, index:, line:, column:, items:)
          return if text[index - 1] !~ /[a-zA-Z0-9]/

          text = text.dup
          argname = [] #: Array[String]
          while text[index - 1] =~ /[a-zA-Z0-9]/
            argname.unshift(text[index - 1] || '')
            source_text[index - 1] = " "
            index -= 1
          end

          begin
            type_check!(source_text, line: line, column: column)
          rescue Parser::SyntaxError
            return
          end

          if nodes = source.find_nodes(line: line, column: column)
            if (send_node, block_node = deconstruct_sendish_and_block_nodes(*nodes))
              position = Position.new(line: line, column: column)
              keyword_argument_items_for_method(
                call_node: block_node || send_node,
                send_node: send_node,
                position: position,
                prefix: argname.join,
                items: items
              )
            end
          end
        end

        def method_items_for_receiver_type(type, include_private:, prefix:, position:, items:)
          range = range_for(position, prefix: prefix)
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

            shape.methods.each do |name, method_entry|
              next if disallowed_method?(name)

              if name.to_s.start_with?(prefix)
                if word_name?(name.to_s)
                  case type
                  when AST::Types::Name::Instance, AST::Types::Name::Interface, AST::Types::Name::Singleton
                    # Simple method type
                    all_decls = Set.new(method_entry.overloads.flat_map {|overload| overload.method_decls(name) }).sort_by {|decl| decl.method_name.to_s }
                    all_members = Set.new(all_decls.flat_map {|decl| decl.method_def.member })
                    all_members.each do |member|
                      associated_decl = all_decls.find {|decl| decl.method_def.member == member } or next
                      overloads = method_entry.overloads.select {|overload| overload.method_defs.any? {|defn| defn.member == member }}
                      annotations = associated_decl.method_def.member_annotations
                      items << SimpleMethodNameItem.new(
                        identifier: name,
                        range: range,
                        receiver_type: type,
                        method_name: associated_decl.method_name,
                        method_types: overloads.map {|overload| subtyping.factory.method_type_1(overload.method_type) },
                        method_member: member,
                        deprecated: AnnotationsHelper.deprecated_annotation?(annotations) ? true : false
                      )
                    end
                  else
                    generated_overloads, defined_overloads =
                      method_entry.overloads.partition {|overload| overload.method_defs.empty? }

                    unless defined_overloads.empty?
                      items << ComplexMethodNameItem.new(
                        identifier: name,
                        range: range,
                        receiver_type: type,
                        method_types: defined_overloads.map { subtyping.factory.method_type_1(_1.method_type) },
                        method_decls: defined_overloads.flat_map { _1.method_decls(name).to_a }.sort_by {|decl| decl.method_name.to_s }
                      )
                    end

                    unless generated_overloads.empty?
                      items << GeneratedMethodNameItem.new(
                        identifier: name,
                        range: range,
                        receiver_type: type,
                        method_types: generated_overloads.map { subtyping.factory.method_type_1(_1.method_type) }
                      )
                    end
                  end
                end
              end
            end
          end
        end

        def word_name?(name)
          name =~ /\w/ ? true : false
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
              const_name = typing.source_index.reference(constant_node: parent) or raise "Unknown node in source_index: #{parent}"
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
              items << InstanceVariableItem.new(identifier: name, range: range, type: type)
            end
          end
        end

        def keyword_argument_items_for_method(call_node:, send_node:, position:, prefix:, items:)
          _receiver_node, _method_name, argument_nodes = deconstruct_send_node!(send_node)

          call = typing.call_of(node: call_node)

          case call
          when TypeInference::MethodCall::Typed, TypeInference::MethodCall::Error
            context = typing.cursor_context.context or raise
            type = call.receiver_type
            type = type.subst(Interface::Substitution.build([], self_type: context.self_type, module_type: context.module_context&.module_type, instance_type: context.module_context&.instance_type))

            config = Interface::Builder::Config.new(self_type: type, variable_bounds: context.variable_context.upper_bounds)
            if shape = subtyping.builder.shape(type, config)
              shape = shape.public_shape if private_send?(call_node)
              if method = shape.methods[call.method_name]
                method.overloads.each.with_index do |overload, i|
                  defn = overload.method_decls(call.method_name).to_a[0]&.method_def
                  if defn && defn.type.type
                    range = range_for(position, prefix: prefix)
                    kwargs = argument_nodes.find { |arg| arg.type == :kwargs }&.children || []
                    used_kwargs = kwargs.filter_map { |arg| arg.type == :pair && arg.children.first.children.first }

                    if defn.type.type.is_a?(::RBS::Types::UntypedFunction)
                      kwargs = [] #: Array[Symbol]
                    else
                      kwargs = defn.type.type.required_keywords.keys + defn.type.type.optional_keywords.keys
                    end

                    kwargs.each do |name|
                      if name.to_s.start_with?(prefix) && !used_kwargs.include?(name)
                        items << KeywordArgumentItem.new(identifier: "#{name}:", range: range)
                      end
                    end
                  end
                end
              end
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

        def unwrap_optional(type)
          if type.is_a?(AST::Types::Union) && type.types.include?(AST::Builtin.nil_type)
            types = type.types.reject { |t| t == AST::Builtin.nil_type }
            AST::Types::Union.new(types: types)
          else
            type
          end
        end
      end
    end
  end
end
