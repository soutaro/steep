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

        def rbs_type(context, subtyping, type_vars)
          if ty = RBS::Parser.parse_type(type_location.buffer, range: type_location.range, variables: type_vars, require_eof: true)
            resolver = RBS::Resolver::TypeNameResolver.build(subtyping.factory.env)
            ty = ty.map_type_name {|name| resolver.resolve(name, context: context) || name.absolute! }
          end
        end

        def type(context, subtyping, type_vars)
          if ty = rbs_type(context, subtyping, type_vars)
            validator = Signature::Validator.new(checker: subtyping)
            validator.rescue_validation_errors do
              validator.validate_type(ty)
            end

            unless validator.has_error?
              subtyping.factory.type(ty)
            else
              validator.each_error.to_a
            end
          else
            nil
          end
        rescue ::RBS::ParsingError => exn
          exn
        end

        def type_syntax?
          RBS::Parser.parse_type(type_location.buffer, range: type_location.range, variables: [], require_eof: true)
        rescue ::RBS::ParsingError
          nil
        end

        def type?(context, subtyping, type_vars)
          type = type(context, subtyping, type_vars)

          case type
          when RBS::ParsingError, nil, Array
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
          source = location.source.strip

          if source =~/\A:\s*(.+)/
            assertion = TypeAssertion.new(location)
            if assertion.type_syntax?
              assertion
            end
          end
        end
      end
    end
  end
end
