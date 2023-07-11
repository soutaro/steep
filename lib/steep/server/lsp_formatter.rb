module Steep
  module Server
    module LSPFormatter
      include Services

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

      def format_hover_content(content)
        case content
        when HoverProvider::Ruby::VariableContent
          local_variable(content.name, content.type)

        when HoverProvider::Ruby::MethodCallContent
          io = StringIO.new
          call = content.method_call

          case call
          when TypeInference::MethodCall::Typed
            io.puts <<~MD
              ```rbs
              #{call.actual_method_type.type.return_type}
              ```

              ----
            MD

            method_types = call.method_decls.map(&:method_type)

            if call.is_a?(TypeInference::MethodCall::Special)
              method_types = [
                call.actual_method_type.with(
                  type: call.actual_method_type.type.with(return_type: call.return_type)
                )
              ]

              header = <<~MD
                **💡 Custom typing rule applies**

                ----
              MD
            end
          when TypeInference::MethodCall::Error
            method_types = call.method_decls.map {|decl| decl.method_type }

            header = <<~MD
              **🚨 No compatible method type found**

              ----
            MD
          end

          method_names = call.method_decls.map {|decl| decl.method_name.relative }
          docs = call.method_decls.map {|decl| [decl.method_name, decl.method_def.comment] }.to_h

          if header
            io.puts header
          end

          io.puts(
            format_method_item_doc(method_types, method_names, docs)
          )

          io.string

        when HoverProvider::Ruby::DefinitionContent
          io = StringIO.new

          method_name =
            if content.method_name.is_a?(SingletonMethodName)
              "self.#{content.method_name.method_name}"
            else
              content.method_name.method_name
            end

          prefix_size = "def ".size + method_name.size
          method_types = content.definition.method_types

          io.puts <<~MD
            ```rbs
            def #{method_name}: #{method_types.join("\n" + " "*prefix_size + "| ") }
            ```

            ----
          MD

          if content.definition.method_types.size > 1
            io.puts "**Internal method type**"
            io.puts <<~MD
              ```rbs
              #{content.method_type}
              ```

              ----
            MD
          end

          io.puts format_comments(
            content.definition.comments.map {|comment|
              [content.method_name.relative.to_s, comment] #: [String, RBS::AST::Comment?]
            }
          )

          io.string
        when HoverProvider::Ruby::ConstantContent
          io = StringIO.new

          decl_summary =
            case
            when decl = content.class_decl
              declaration_summary(decl.primary.decl)
            when decl = content.constant_decl
              declaration_summary(decl.decl)
            when decl = content.class_alias
              declaration_summary(decl.decl)
            end

          io.puts <<~MD
            ```rbs
            #{decl_summary}
            ```
          MD

          comments = content.comments.map {|comment|
            [content.full_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
          }

          unless comments.all?(&:nil?)
            io.puts "----"
            io.puts format_comments(comments)
          end

          io.string
        when HoverProvider::Ruby::TypeContent
          <<~MD
            ```rbs
            #{content.type}
            ```
          MD

        when HoverProvider::Ruby::TypeAssertionContent
          <<~MD
            ```rbs
            #{content.asserted_type}
            ```

            ↑ Converted from `#{content.original_type.to_s}`
          MD

        when HoverProvider::RBS::TypeAliasContent, HoverProvider::RBS::InterfaceContent
          io = StringIO.new()

          io.puts <<~MD
            ```rbs
            #{declaration_summary(content.decl)}
            ```
          MD

          if comment = content.decl.comment
            io.puts
            io.puts "----"

            io.puts format_comment(comment, header: content.decl.name.relative!.to_s)
          end

          io.string

        when HoverProvider::RBS::ClassContent
          io = StringIO.new

          io << <<~MD
          ```rbs
          #{declaration_summary(content.decl)}
          ```
          MD

          if content.decl.comment
            io.puts "----"

            class_name =
              case content.decl
              when RBS::AST::Declarations::ModuleAlias, RBS::AST::Declarations::ClassAlias
                content.decl.new_name
              when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
                content.decl.name
              else
                raise
              end

            io << format_comments([[class_name.relative!.to_s, content.decl.comment]])
          end

          io.string
        else
          raise content.class.to_s
        end
      end

      def format_completion_docs(item)
        case item
        when Services::CompletionProvider::LocalVariableItem
          local_variable(item.identifier, item.type)
        when Services::CompletionProvider::ConstantItem
          io = StringIO.new

          io.puts <<~MD
            ```rbs
            #{declaration_summary(item.decl)}
            ```
          MD

          unless item.comments.all?(&:nil?)
            io.puts "----"
            io.puts format_comments(
              item.comments.map {|comment|
                [item.full_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
              }
            )
          end

          io.string
        when Services::CompletionProvider::InstanceVariableItem
          instance_variable(item.identifier, item.type)
        when Services::CompletionProvider::SimpleMethodNameItem
          format_method_item_doc(item.method_types, [], { item.method_name => item.method_member.comment })
        when Services::CompletionProvider::ComplexMethodNameItem
          method_names = item.method_names.map(&:relative).uniq
          comments = item.method_definitions.transform_values {|member| member.comment }
          format_method_item_doc(item.method_types, method_names, comments)
        when Services::CompletionProvider::GeneratedMethodNameItem
          format_method_item_doc(item.method_types, [], {}, "🤖 Generated method for receiver type")
        when Services::CompletionProvider::TypeNameItem
          io = StringIO.new

          io.puts <<~MD
            ```rbs
            #{declaration_summary(item.decl)}
            ```
          MD

          unless item.comments.empty?
            io.puts "----"
            io.puts format_comments(
              item.comments.map {|comment|
                [item.absolute_type_name.relative!.to_s, comment] #: [String, RBS::AST::Comment?]
              }
            )
          end

          io.string
        when Services::CompletionProvider::KeywordArgumentItem
          <<~MD
            **Keyword argument**: `#{item.identifier}`
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
            s = ""
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

            if param.upper_bound
              s << " < #{param.upper_bound.to_s}"
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
