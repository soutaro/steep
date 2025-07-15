module Steep
  module Services
    module CompletionProvider
      class RBS
        attr_reader :project, :signature, :path

        def initialize(path, signature)
          @path = path
          @signature = signature
        end

        def run(line, column)
          context = nil #: RBS::Resolver::context

          case signature.status
          when Services::SignatureService::SyntaxErrorStatus, Services::SignatureService::AncestorErrorStatus
            if source = signature.latest_env.each_rbs_source.find { _1.buffer.name == path }
              dirs = source.directives
            else
              dirs = [] #: Array[RBS::AST::Directives::t]
            end
          else
            file = signature.files.fetch(path)
            file.is_a?(Services::SignatureService::RBSFileStatus) or raise
            source = file.source
            source.is_a?(::RBS::Source::RBS) or raise
            buffer = source.buffer
            dirs = source.directives
            decls = source.declarations

            locator = ::RBS::Locator.new(buffer: buffer, dirs: dirs, decls: decls)

            _hd, tail = locator.find2(line: line, column: column)
            tail ||= [] #: Array[RBS::Locator::component]

            tail.reverse_each do |t|
              case t
              when ::RBS::AST::Declarations::Module, ::RBS::AST::Declarations::Class
                if (last_type_name = context&.[](1)).is_a?(::RBS::TypeName)
                  context = [context, last_type_name + t.name]
                else
                  context = [context, t.name.absolute!]
                end
              end
            end
          end

          content =
            case file = signature.files.fetch(path)
            when ::RBS::Source::Ruby
              file.buffer.content
            when Services::SignatureService::RBSFileStatus
              file.content
            end
          buffer = ::RBS::Buffer.new(name: path, content: content)
          prefix = Services::CompletionProvider::TypeName::Prefix.parse(buffer, line: line, column: column)

          completion = Services::CompletionProvider::TypeName.new(env: signature.latest_env, context: context, dirs: dirs)
          type_names = completion.find_type_names(prefix)
          prefix_size = prefix ? prefix.size : 0

          [
            prefix_size,
            type_names.map do |type_name|
              absolute_name, relative_name = completion.resolve_name_in_context(type_name)
              [absolute_name, relative_name]
            end
          ]
        end
      end
    end
  end
end
