module Steep
  module AST
    module Types
      class Proc
        attr_reader :location
        attr_reader :type

        def initialize(type:, location: type.location)
          @type = type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) && other.type == type
        end

        def hash
          self.class.hash && type.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(
            type: type.subst(s),
            location: location
          )
        end

        def to_s
          "^#{type.params} -> #{type.return_type}"
        end

        def free_variables()
          @fvs ||= type.free_variables
        end

        def level
          children = type.params.each_type.to_a + [type.return_type]
          [0] + level_of_children(children)
        end

        def closed?
          type.params.closed? && type.return_type.closed?
        end

        def with_location(new_location)
          self.class.new(location: new_location, type: type)
        end

        def map_type(&block)
          self.class.new(
            type: type.map_type(&block),
            location: location
          )
        end

        def one_arg?
          params = type.params

          params.required.size == 1 &&
            params.optional.empty? &&
            !params.rest &&
            params.required_keywords.empty? &&
            params.optional_keywords.empty? &&
            !params.rest_keywords
        end

        def back_type
          Name::Instance.new(name: Builtin::Proc.module_name,
                             args: [],
                             location: location)
        end
      end
    end
  end
end
