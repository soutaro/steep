module Steep
  module AST
    module Node
      class TypeApplication
        attr_reader :location

        def initialize(location)
          @location = location
        end

        def node
          @node || raise
        end

        def set_node(node)
          @node = node
        end

        def line
          location.start_line
        end

        def source
          location.source
        end

        def types(context, factory, type_vars)
          # @type var types: Array[Types::t]
          types = []

          loc = type_location

          while true
            ty = RBS::Parser.parse_type(loc.buffer, range: loc.range, variables: type_vars) or break
            ty = factory.type(ty)
            types << factory.absolute_type(ty, context: context)

            match = RBS::Location.new(loc.buffer, ty.location.end_pos, type_location.end_pos).source.match(/\A\s*,\s*/) or break
            offset = match.length
            loc = RBS::Location.new(loc.buffer, ty.location.end_pos + offset, type_location.end_pos)
          end

          types
        rescue ::RBS::ParsingError => exn
          exn
        end

        def types?(context, factory, type_vars)
          case types = types(context, factory, type_vars)
          when RBS::ParsingError
            nil
          else
            types
          end
        end

        def type_str
          @type_str ||= source.delete_prefix("$").lstrip
        end

        def type_location
          offset = source.size - type_str.size
          RBS::Location.new(location.buffer, location.start_pos + offset, location.end_pos)
        end

        def self.parse(location)
          if location.source =~/\A\$\s*(.+)/
            TypeApplication.new(location)
          end
        end
      end
    end
  end
end
