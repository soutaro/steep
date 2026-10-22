module Steep
  module Server
    module LSPFormatter
      LSP = LanguageServer::Protocol

      module_function

      def markup_content(string = nil, &block)
        if block
          string = yield()
        end

        if string
          LSP::Interface::MarkupContent.new(kind: LSP::Constant::MarkupKind::MARKDOWN, value: string)
        end
      end

      def hover(result, service:)
        env, builder = environment_of(result[:target], service)

        LSP::Interface::Hover.new(
          contents: LSP::Interface::MarkupContent.new(
            kind: LSP::Constant::MarkupKind::MARKDOWN,
            value: format_hover_content(result[:content], env: env, builder: builder)
          ),
          range: lsp_range(result[:range])
        )
      end

      def completion_list(result, service:)
        env, builder = environment_of(result[:target], service)

        LSP::Interface::CompletionList.new(
          is_incomplete: result[:incomplete],
          items: result[:items].map {|item| completion_item(item, env: env, builder: builder) }
        )
      end

      def signature_help(result, service:)
        _, builder = environment_of(result[:target], service)

        signatures = result[:signatures].map do |signature|
          comment =
            if method = signature[:method]
              method_definitions(MethodName(method), builder: builder).first&.comment
            end

          LSP::Interface::SignatureInformation.new(
            label: signature[:method_type],
            parameters: signature[:parameters].map {|param| LSP::Interface::ParameterInformation.new(label: param) },
            active_parameter: signature[:active_parameter],
            documentation: comment&.yield_self do |comment|
              LSP::Interface::MarkupContent.new(
                kind: LSP::Constant::MarkupKind::MARKDOWN,
                value: comment.string.gsub(/<!--(?~-->)-->/, "")
              )
            end
          )
        end

        LSP::Interface::SignatureHelp.new(
          signatures: signatures,
          active_signature: result[:active_signature]
        )
      end

      def environment_of(target, service)
        # Read the status once, so that the environment and the builder are of the same generation
        builder = service.signature_services.fetch(target.to_sym).latest_builder
        [builder.env, builder]
      end

      def lsp_range(range)
        LSP::Interface::Range.new(
          start: LSP::Interface::Position.new(line: range[:start][:line], character: range[:start][:character]),
          end: LSP::Interface::Position.new(line: range[:end][:line], character: range[:end][:character])
        )
      end

      def kind_of(record)
        # Reading a key of a union of records is very slow in Steep, so the kind is read as untyped
        (_ = record)[:kind]
      end

      def format_hover_content(content, env:, builder:)
        kind = kind_of(content)

        case kind
        when "variable"
          content = content #: CustomMethods::Hover::variable_content
          local_variable(content[:name], content[:type])

        when "type"
          content = content #: CustomMethods::Hover::type_content
          <<~MD
            ```rbs
            #{content[:type]}
            ```
          MD

        when "type_assertion"
          content = content #: CustomMethods::Hover::type_assertion_content
          <<~MD
            ```rbs
            #{content[:asserted_type]}
            ```

            ↑ Converted from `#{content[:original_type]}`
          MD

        when "method_call"
          content = content #: CustomMethods::Hover::method_call_content
          io = StringIO.new

          unless content[:error]
            io.puts <<~MD
              ```rbs
              #{content[:return_type]}
              ```

              ----
            MD
          end

          if content[:special]
            io.puts <<~MD
              **💡 Custom typing rule applies**

              ----
            MD
          end

          if content[:error]
            io.puts <<~MD
              **🚨 No compatible method type found**

              ----
            MD
          end

          method_names = content[:methods].map {|name| MethodName(name) }
          docs = method_names.uniq.each_with_object({}) do |method_name, hash| #$ Hash[method_name, RBS::AST::Comment?]
            hash[method_name] = method_definitions(method_name, builder: builder).filter_map(&:comment).last
          end

          io.puts(
            format_method_item_doc(content[:method_types], method_names.map(&:relative), docs)
          )

          io.string

        when "definition"
          content = content #: CustomMethods::Hover::definition_content
          io = StringIO.new

          method_name = MethodName(content[:method])
          name_string =
            if method_name.is_a?(SingletonMethodName)
              "self.#{method_name.method_name}"
            else
              method_name.method_name.to_s
            end

          prefix_size = "def ".size + name_string.size
          method_types = content[:method_types]

          io.puts <<~MD
            ```rbs
            def #{name_string}: #{method_types.join("\n" + " "*prefix_size + "| ") }
            ```

            ----
          MD

          if method_types.size > 1
            io.puts "**Internal method type**"
            io.puts <<~MD
              ```rbs
              #{content[:method_type]}
              ```

              ----
            MD
          end

          comments = method_definition(method_name, builder: builder)&.comments || []
          io.puts format_comments(
            comments.map {|comment|
              [method_name.relative.to_s, comment] #: [String, RBS::AST::Comment?]
            }
          )

          io.string

        when "constant"
          content = content #: CustomMethods::Hover::constant_content
          io = StringIO.new

          full_name = RBS::TypeName.parse(content[:name])
          decl, comments = constant_decl(full_name, env: env)

          io.puts <<~MD
            ```rbs
            #{decl ? declaration_summary(decl) : full_name.relative!}
            ```
          MD

          comments = comments.compact.map {|comment|
            [full_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
          }

          unless comments.empty?
            io.puts "----"
            io.puts format_comments(comments)
          end

          io.string

        when "type_name"
          content = content #: CustomMethods::Hover::type_name_content
          io = StringIO.new

          type_name = RBS::TypeName.parse(content[:name])
          decl = type_name_decl(type_name, env: env)

          io.puts <<~MD
            ```rbs
            #{decl ? declaration_summary(decl) : type_name.relative!}
            ```
          MD

          case decl
          when RBS::AST::Declarations::TypeAlias, RBS::AST::Declarations::Interface
            if comment = decl.comment
              io.puts
              io.puts "----"
              io.puts format_comment(comment, header: decl.name.relative!.to_s)
            end
          when RBS::AST::Declarations::Base
            if comment = decl.comment
              io.puts "----"
              io << format_comments([[type_name.relative!.to_s, comment]])
            end
          end

          io.string

        else
          raise "Unknown hover content: #{kind}"
        end
      end

      def completion_item(item, env:, builder:)
        kind = kind_of(item)

        case kind
        when "local_variable"
          item = item #: CustomMethods::Completion::local_variable_item
          name = item[:name]

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: LSP::Constant::CompletionItemKind::VARIABLE,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: item[:type]),
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            insert_text: name,
            sort_text: name
          )

        when "instance_variable"
          item = item #: CustomMethods::Completion::instance_variable_item
          name = item[:name]

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: LSP::Constant::CompletionItemKind::FIELD,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: item[:type]),
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: name)
          )

        when "constant"
          item = item #: CustomMethods::Completion::constant_item
          name = item[:name]
          full_name = RBS::TypeName.parse(item[:full_name])
          decl, _ = constant_decl(full_name, env: env)

          kind =
            if env.class_entry(full_name) || env.module_entry(full_name)
              LSP::Constant::CompletionItemKind::CLASS
            else
              LSP::Constant::CompletionItemKind::CONSTANT
            end

          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          if AnnotationsHelper.deprecated_type_name?(full_name, env)
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: kind,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: decl ? declaration_summary(decl) : nil),
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: name),
            tags: tags
          )

        when "method"
          item = item #: CustomMethods::Completion::method_item
          name = item[:name]
          method_names = item[:methods].map {|method| MethodName(method) }.uniq

          description =
            if method_names.empty?
              "(Generated)"
            else
              method_names.map {|method_name| method_name.relative.to_s }.uniq.join(", ")
            end

          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          deprecated = method_names.any? do |method_name|
            method_definitions(method_name, builder: builder).any? {|defn| AnnotationsHelper.deprecated_annotation?(defn.member_annotations) }
          end
          if deprecated
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: LSP::Constant::CompletionItemKind::FUNCTION,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: description),
            insert_text: name,
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            tags: tags
          )

        when "keyword_argument"
          item = item #: CustomMethods::Completion::keyword_argument_item
          name = item[:name]

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: LSP::Constant::CompletionItemKind::FIELD,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: 'Keyword argument'),
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: name)
          )

        when "type_name"
          item = item #: CustomMethods::Completion::type_name_item
          name = item[:name]
          type_name = RBS::TypeName.parse(item[:full_name])
          decl = type_name_decl(type_name, env: env)

          kind =
            case
            when type_name.class?
              LSP::Constant::CompletionItemKind::CLASS
            when type_name.interface?
              LSP::Constant::CompletionItemKind::INTERFACE
            when type_name.alias?
              LSP::Constant::CompletionItemKind::FIELD
            end

          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          if AnnotationsHelper.deprecated_type_name?(type_name, env)
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: name,
            kind: kind,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: decl ? declaration_summary(decl) : nil),
            documentation: markup_content { format_completion_docs(item, env: env, builder: builder) },
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: name),
            tags: tags
          )

        when "builtin_type"
          item = item #: CustomMethods::Completion::builtin_type_item
          name = item[:name]

          LSP::Interface::CompletionItem.new(
            label: name,
            detail: "(builtin type)",
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: name),
            kind: LSP::Constant::CompletionItemKind::KEYWORD,
            filter_text: name,
            sort_text: "zz__#{name}"
          )

        when "text"
          item = item #: CustomMethods::Completion::text_item
          help_text = item[:help_text]

          LSP::Interface::CompletionItem.new(
            label: item[:label],
            label_details: help_text && LSP::Interface::CompletionItemLabelDetails.new(description: help_text),
            kind: LSP::Constant::CompletionItemKind::SNIPPET,
            insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET,
            text_edit: LSP::Interface::TextEdit.new(range: lsp_range(item[:range]), new_text: item[:text])
          )

        else
          raise "Unknown completion item: #{kind}"
        end
      end

      def format_completion_docs(item, env:, builder:)
        case kind_of(item)
        when "local_variable"
          item = item #: CustomMethods::Completion::local_variable_item
          local_variable(item[:name], item[:type])

        when "instance_variable"
          item = item #: CustomMethods::Completion::instance_variable_item
          instance_variable(item[:name], item[:type])

        when "constant"
          item = item #: CustomMethods::Completion::constant_item
          io = StringIO.new

          full_name = RBS::TypeName.parse(item[:full_name])
          decl, comments = constant_decl(full_name, env: env)

          io.puts <<~MD
            ```rbs
            #{decl ? declaration_summary(decl) : full_name.relative!}
            ```
          MD

          unless comments.all?(&:nil?)
            io.puts "----"
            io.puts format_comments(
              comments.map {|comment|
                [full_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
              }
            )
          end

          io.string

        when "method"
          item = item #: CustomMethods::Completion::method_item
          method_names = item[:methods].map {|method| MethodName(method) }.uniq
          method_types = item[:method_types]

          if method_names.empty?
            format_method_item_doc(method_types, [], {}, "🤖 Generated method for receiver type")
          else
            comments = method_names.each_with_object({}) do |method_name, hash| #$ Hash[method_name, RBS::AST::Comment?]
              hash[method_name] = method_definitions(method_name, builder: builder).filter_map(&:comment).last
            end
            format_method_item_doc(method_types, method_names.map(&:relative).uniq, comments)
          end

        when "type_name"
          item = item #: CustomMethods::Completion::type_name_item
          type_name = RBS::TypeName.parse(item[:full_name])

          if decl = type_name_decl(type_name, env: env)
            format_rbs_completion_docs(type_name, decl, type_name_comments(type_name, env: env))
          else
            <<~MD
              ```rbs
              #{type_name.relative!}
              ```
            MD
          end

        when "keyword_argument"
          item = item #: CustomMethods::Completion::keyword_argument_item
          <<~MD
            **Keyword argument**: `#{item[:name]}`
          MD
        end
      end

      def format_rbs_completion_docs(type_name, decl, comments)
        io = StringIO.new

        io.puts <<~MD
        ```rbs
        #{declaration_summary(decl)}
        ```
        MD

        unless comments.empty?
          io.puts
          io.puts "----"

          io.puts format_comments(
            comments.map {|comment|
              [type_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
            }
          )
        end

        io.string
      end

      def method_definition(method_name, builder:)
        type_name = method_name.type_name
        env = builder.env

        definition =
          case method_name
          when InstanceMethodName
            if type_name.interface?
              env.interface_decls.key?(type_name) or return
              builder.build_interface(type_name)
            else
              env.module_class_entry(type_name) or return
              builder.build_instance(type_name)
            end
          when SingletonMethodName
            env.module_class_entry(type_name) or return
            builder.build_singleton(type_name)
          end

        definition.methods[method_name.method_name]
      rescue RBS::BaseError => exn
        Steep.logger.warn { "Cannot resolve the definition of #{method_name}: #{exn.inspect}" }
        nil
      end

      def method_definitions(method_name, builder:)
        definition = method_definition(method_name, builder: builder) or return []

        defs = definition.defs.select {|defn| defn.defined_in == method_name.type_name }
        defs.empty? ? definition.defs : defs
      end

      def type_name_decl(type_name, env:)
        case
        when type_name.alias?
          env.type_alias_decls.fetch(type_name, nil)&.decl
        when type_name.interface?
          env.interface_decls.fetch(type_name, nil)&.decl
        when type_name.class?
          case entry = env.module_class_entry(type_name)
          when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
            entry.primary_decl
          when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
            entry.decl
          end
        end
      end

      def type_name_comments(type_name, env:)
        comments = [] #: Array[RBS::AST::Comment]

        case
        when type_name.alias?
          if comment = env.type_alias_decls.fetch(type_name, nil)&.decl&.comment
            comments << comment
          end
        when type_name.interface?
          if comment = env.interface_decls.fetch(type_name, nil)&.decl&.comment
            comments << comment
          end
        when type_name.class?
          case entry = env.module_class_entry(type_name)
          when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
            entry.each_decl do |decl|
              if decl.is_a?(RBS::AST::Declarations::Base)
                if comment = decl.comment
                  comments << comment
                end
              end
            end
          when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
            if comment = entry.decl.comment
              comments << comment
            end
          end
        end

        comments
      end

      def constant_decl(full_name, env:)
        case entry = env.constant_entry(full_name)
        when RBS::Environment::ConstantEntry
          [entry.decl, [entry.decl.comment]]
        when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
          comments = entry.each_decl.map do |decl|
            if decl.is_a?(RBS::AST::Declarations::Base)
              decl.comment
            end
          end
          [entry.primary_decl, comments]
        when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
          [entry.decl, [entry.decl.comment]]
        else
          [nil, []]
        end
      end

      def format_comments(comments)
        io = StringIO.new

        with_docs = [] #: Array[[String, RBS::AST::Comment]]
        without_docs = [] #: Array[String]

        comments.each do |title, comment|
          if comment
            with_docs << [title, comment]
          else
            without_docs << title
          end
        end

        unless with_docs.empty?
          with_docs.each do |title, comment|
            io.puts format_comment(comment, header: title)
            io.puts
          end

          unless without_docs.empty?
            io.puts
            io.puts "----"
            if without_docs.size == 1
              io.puts "🔍 One more definition without docs"
            else
              io.puts "🔍 #{without_docs.size} more definitions without docs"
            end
          end
        end

        io.string
      end

      def format_comment(comment, header: nil, &block)
        return unless comment

        io = StringIO.new
        if header
          io.puts "### 📚 #{header.gsub("_", "\\_")}"
          io.puts
        end
        io.puts comment.string.rstrip.gsub(/^[ \t]*<!--(?~-->)-->\n/, "").gsub(/\A([ \t]*\n)+/, "")

        if block
          yield io.string
        else
          io.string
        end
      end

      def local_variable(name, type)
        <<~MD
          **Local variable** `#{name}: #{type}`
        MD
      end

      def instance_variable(name, type)
        <<~MD
          **Instance variable** `#{name}: #{type}`
        MD
      end

      def name_and_params(name, params)
        if params.empty?
          "#{name}"
        else
          ps = params.each.map do |param|
            s = +""
            if param.unchecked?
              s << "unchecked "
            end
            case param.variance
            when :invariant
              # nop
            when :covariant
              s << "out "
            when :contravariant
              s << "in "
            end
            s << param.name.to_s

            if param.upper_bound_type
              s << " < #{param.upper_bound_type.to_s}"
            end

            s
          end

          "#{name}[#{ps.join(", ")}]"
        end
      end

      def name_and_args(name, args)
        if args.empty?
          "#{name}"
        else
          "#{name}[#{args.map(&:to_s).join(", ")}]"
        end
      end

      def declaration_summary(decl)
        # Note that all names in the declarations is absolute
        case decl
        when RBS::AST::Declarations::Class
          super_class = if super_class = decl.super_class
                          " < #{name_and_args(super_class.name, super_class.args)}"
                        end
          "class #{name_and_params(decl.name.relative!, decl.type_params)}#{super_class}"
        when RBS::AST::Declarations::Module
          self_type = unless decl.self_types.empty?
                        " : #{decl.self_types.map {|s| name_and_args(s.name, s.args) }.join(", ")}"
                      end
          "module #{name_and_params(decl.name.relative!, decl.type_params)}#{self_type}"
        when RBS::AST::Declarations::TypeAlias
          "type #{name_and_params(decl.name.relative!, decl.type_params)} = #{decl.type}"
        when RBS::AST::Declarations::Interface
          "interface #{name_and_params(decl.name.relative!, decl.type_params)}"
        when RBS::AST::Declarations::ClassAlias
          "class #{decl.new_name.relative!} = #{decl.old_name}"
        when RBS::AST::Declarations::ModuleAlias
          "module #{decl.new_name.relative!} = #{decl.old_name}"
        when RBS::AST::Declarations::Global
          "#{decl.name}: #{decl.type}"
        when RBS::AST::Declarations::Constant
          "#{decl.name.relative!}: #{decl.type}"
        when RBS::AST::Ruby::Declarations::ClassDecl
          "class #{decl.class_name.relative!}"
        when RBS::AST::Ruby::Declarations::ModuleDecl
          "module #{decl.module_name.relative!}"
        when RBS::AST::Ruby::Declarations::ConstantDecl
          "#{decl.constant_name.relative!}: #{decl.type}"
        when RBS::AST::Ruby::Declarations::ClassModuleAliasDecl
          keyword =
            if decl.annotation.is_a?(RBS::AST::Ruby::Annotations::ClassAliasAnnotation)
              "class"
            else
              "module"
            end
          "#{keyword} #{decl.new_name} = #{decl.old_name}"
        end
      end

      def format_method_item_doc(method_types, method_names, comments, footer = "")
        io = StringIO.new

        io.puts "**Method type**:"
        io.puts "```rbs"
        if method_types.size == 1
          io.puts method_types[0].to_s
        else
          io.puts "  #{method_types.join("\n| ")}"
        end
        io.puts "```"

        if method_names.size > 1
          io.puts "**Possible methods**: #{method_names.map {|type| "`#{type.to_s}`" }.join(", ")}"
          io.puts
        end

        unless comments.each_value.all?(&:nil?)
          io.puts "----"
          io.puts format_comments(comments.transform_keys {|name| name.relative.to_s }.entries)
        end

        unless footer.empty?
          io.puts footer.rstrip
        end

        io.string
      end
    end
  end
end
