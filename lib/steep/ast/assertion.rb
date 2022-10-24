module Steep
  module AST
    module Assertion
      class Base
        attr_reader :source, :location

        def initialize(source, location)
          @source = source
          @location = location
        end

        def line
          location.start_line
        end
      end

      class AsType < Base
        def type(context, factory, type_vars)
          ty = RBS::Parser.parse_type(type_str, line: location.start_line, column: location.start_column, variables: type_vars)
          ty = factory.type(ty)
          factory.absolute_type(ty, context: context)
        rescue ::RBS::ParsingError => exn
          exn
        end

        def type?(context, factory, type_vars)
          case type = type(context, factory, type_vars)
          when RBS::ParsingError
            nil
          else
            type
          end
        end

        def type_str
          source.delete_prefix(":").lstrip
        end
      end

      def self.parse(source, location)
        case source
        when /\A:\s*(.+)/
          AsType.new(source, location)
        end
      end
    end
  end
end
