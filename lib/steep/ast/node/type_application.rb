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

        def types(context, subtyping, type_vars)
          # @type var types: Array[LocatedValue[Types::t]]
          types = []

          each_rbs_type(context, subtyping, type_vars) do |rbs_ty|
            validator = Signature::Validator.new(checker: subtyping)
            validator.rescue_validation_errors do
              validator.validate_type(rbs_ty)
            end

            if validator.has_error?
              return validator.each_error
            end

            ty = subtyping.factory.type(rbs_ty)
            types << LocatedValue.new(value: ty, location: rbs_ty.location || raise)
          end

          types
        rescue ::RBS::ParsingError => exn
          exn
        end

        def types?(context, subtyping, type_vars)
          case types = types(context, subtyping, type_vars)
          when RBS::ParsingError, Enumerator
            nil
          else
            types
          end
        end

        def each_rbs_type(context, subtyping, type_vars)
          resolver = RBS::Resolver::TypeNameResolver.build(subtyping.factory.env)

          loc = type_location

          while true
            type = RBS::Parser.parse_type(loc.buffer, range: loc.range, variables: type_vars) or break
            type_loc = type.location or raise
            type = type.map_type_name {|name| resolver.resolve(name, context: context) || name.absolute! }

            yield type

            match = RBS::Location.new(loc.buffer, type_loc.end_pos, type_location.end_pos).source.match(/\A\s*,\s*/) or break
            offset = match.length
            loc = RBS::Location.new(loc.buffer, type_loc.end_pos + offset, type_location.end_pos)
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
