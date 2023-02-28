module Steep
  module Server
    module LSPFormatter
      include Services

      class CommentBuilder
        def initialize
          @array = []
        end

        def self.build
          builder = CommentBuilder.new
          yield builder
          builder.to_s
        end

        def to_s
          unless @array.empty?
            @array.join("\n\n----\n\n")
          else
            ""
          end
        end

        def <<(string)
          if string
            s = string.rstrip.gsub(/^[ \t]*<!--(?~-->)-->\n/, "").gsub(/\A([ \t]*\n)+/, "")
            unless @array.include?(s)
              @array << s
            end
          end
        end

        def push
          s = ""
          yield s
          self << s
        end
      end

      module_function

      def format_hover_content(content)
        case content
        when HoverProvider::Ruby::VariableContent
          "`#{content.name}`: `#{content.type.to_s}`"

        when HoverProvider::Ruby::MethodCallContent
          CommentBuilder.build do |builder|
            call = content.method_call
            builder.push do |s|
              case call
              when TypeInference::MethodCall::Special
                mt = call.actual_method_type.with(
                  type: call.actual_method_type.type.with(return_type: call.return_type)
                )
                s << <<-EOM
**💡 Custom typing rule applies**

```rbs
#{mt.to_s}
```

                EOM
              when TypeInference::MethodCall::Typed
                mt = call.actual_method_type.with(
                  type: call.actual_method_type.type.with(return_type: call.return_type)
                )
                s << "```rbs\n#{mt.to_s}\n```\n\n"
              when TypeInference::MethodCall::Error
                s << "```rbs\n( ??? ) -> #{call.return_type.to_s}\n```\n\n"
              end

              s << to_list(call.method_decls) do |decl|
                "`#{decl.method_name}`"
              end
            end

            call.method_decls.each do |decl|
              if comment = decl.method_def.comment
                builder << <<EOM
**#{decl.method_name.to_s}**

```rbs
#{decl.method_type}
```

#{comment.string.gsub(/\A([ \t]*\n)+/, "")}
EOM
              end
            end
          end

        when HoverProvider::Ruby::DefinitionContent
          CommentBuilder.build do |builder|
            builder << <<EOM
```
#{content.method_name}: #{content.method_type}
```
EOM
            if comments = content.definition&.comments
              comments.each do |comment|
                builder << comment.string
              end
            end

            if content.definition.method_types.size > 1
              builder << to_list(content.definition.method_types) {|type| "`#{type.to_s}`" }
            end
          end
        when HoverProvider::Ruby::ConstantContent
          CommentBuilder.build do |builder|
            case
            when decl = content.class_decl
              builder << <<EOM
```rbs
#{declaration_summary(decl.primary.decl)}
```
EOM
            when decl = content.constant_decl
              builder << <<EOM
```rbs
#{content.full_name}: #{content.type}
```
EOM
            when decl = content.class_alias
              builder << <<EOM
```rbs
#{decl.is_a?(::RBS::Environment::ClassAliasEntry) ? "class" : "module"} #{decl.decl.new_name} = #{decl.decl.old_name}
```
EOM
            end

            content.comments.each do |comment|
              builder << comment.string
            end
          end
        when HoverProvider::Ruby::TypeContent
          "`#{content.type}`"
        when HoverProvider::RBS::TypeAliasContent
          CommentBuilder.build do |builder|
            builder << <<EOM
```rbs
#{declaration_summary(content.decl)}
```
EOM
            if comment = content.decl.comment
              builder << comment.string
            end
          end
        when HoverProvider::Ruby::TypeAssertionContent
          CommentBuilder.build do |builder|
            builder << <<-EOM
`#{content.asserted_type.to_s}`

↑ Converted from `#{content.original_type.to_s}`
            EOM
          end
        when HoverProvider::RBS::ClassContent
          CommentBuilder.build do |builder|
            builder << <<EOM
```rbs
#{declaration_summary(content.decl)}
```
EOM
            if comment = content.decl.comment
              builder << comment.string
            end
          end
        when HoverProvider::RBS::InterfaceContent
          CommentBuilder.build do |builder|
            builder << <<EOM
```rbs
#{declaration_summary(content.decl)}
```
EOM
            if comment = content.decl.comment
              builder << comment.string
            end
          end
        else
          raise content.class.to_s
        end
      end

      def to_list(collection, &block)
        buffer = ""

        strings =
          if block
            collection.map(&block)
          else
            collection.map(&:to_s)
          end

        strings.each do |s|
          buffer << "- #{s}\n"
        end

        buffer
      end

      def name_and_args(name, args)
        if args.empty?
          "#{name}"
        else
          "#{name}[#{args.map(&:to_s).join(", ")}]"
        end
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

      def declaration_summary(decl)
        case decl
        when RBS::AST::Declarations::Class
          super_class = if super_class = decl.super_class
                          " < #{name_and_args(super_class.name, super_class.args)}"
                        end
          "class #{name_and_params(decl.name, decl.type_params)}#{super_class}"
        when RBS::AST::Declarations::Module
          self_type = unless decl.self_types.empty?
                        " : #{decl.self_types.map {|s| name_and_args(s.name, s.args) }.join(", ")}"
                      end
          "module #{name_and_params(decl.name, decl.type_params)}#{self_type}"
        when RBS::AST::Declarations::TypeAlias
          "type #{decl.name} = #{decl.type}"
        when RBS::AST::Declarations::Interface
          "interface #{name_and_params(decl.name, decl.type_params)}"
        when RBS::AST::Declarations::ClassAlias
          "class #{decl.new_name} = #{decl.old_name}"
        when RBS::AST::Declarations::ModuleAlias
          "module #{decl.new_name} = #{decl.old_name}"
        end
      end
    end
  end
end
