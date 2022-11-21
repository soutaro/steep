module Steep
  module AST
    module Node
      class TypeAssertion
        attr_reader :location

        def initialize(location)
          @location = location
        end

        def source
          location.source
        end

        def line
          location.start_line
        end

        def type(context, factory, type_vars)
          if ty = RBS::Parser.parse_type(type_location.buffer, range: type_location.range, variables: type_vars)
            ty = factory.type(ty)
            factory.absolute_type(ty, context: context)
          else
            nil
          end
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
          @type_str ||= source.delete_prefix(":").lstrip
        end

        def type_location
          offset = source.size - type_str.size
          RBS::Location.new(location.buffer, location.start_pos + offset, location.end_pos)
        end

        def self.parse(location)
          if location.source =~/\A:\s*(.+)/
            TypeAssertion.new(location)
          end
        end
      end
    end
  end
end
