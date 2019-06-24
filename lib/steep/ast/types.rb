module Steep
  module AST
    module Types
      class Masked
        attr_reader :location
        attr_reader :type
        attr_reader :mask

        def initialize(type:, mask:, location:)
          @type = type
          @mask = mask
          @location = location
        end

        def ==(other)
          other.is_a?(Masked) &&
            other.type == type &&
            other.mask == mask
        end

        alias eql? ==

        def hash
          self.class.hash ^ type.hash ^ mask.hash
        end

        def to_json(*a)
          { class: :masked,
            type: type,
            mask: mask,
            location: location }.to_json(*a)
        end

        def to_s(level = 0)
          "masked(#{type}|#{mask})"
        end

        def free_variables(set = Set.new)
          type.free_variables(set)
          mask.free_variables(set)
        end

        def each_type(&block)
          if block_given?
            yield type
            yield mask
          else
            enum_for :each_type
          end
        end

        def sub(s)
          self.class.new(type: type.sub(s),
                         mask: mask.sub(s),
                         location: location)
        end
      end
    end
  end
end
