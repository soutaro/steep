module Steep
  module AST
    module Types
      class Proc
        attr_reader :location
        attr_reader :params
        attr_reader :return_type

        def initialize(params:, return_type:, location: nil)
          @location = location
          @params = params
          @return_type = return_type
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.params == params &&
            other.return_type == return_type
        end

        def hash
          self.class.hash && params.hash && return_type.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(
            params: params.subst(s),
            return_type: return_type.subst(s),
            location: location
          )
        end

        def to_s
          "#{params} -> #{return_type}"
        end

        def free_variables
          params.free_variables + return_type.free_variables
        end

        def level
          children = params.each_type.to_a + [return_type]
          [0] + level_of_children(children)
        end

        def closed?
          params.closed? && return_type.closed?
        end

        def with_location(new_location)
          self.class.new(location: new_location)
        end

        def map_type(&block)
          self.class.new(
            params: params.map_type(&block),
            return_type: yield(return_type),
            location: location
          )
        end

        # def back_type
        #   Name.new_instance(name: "::NilClass", location: location)
        # end
      end
    end
  end
end
