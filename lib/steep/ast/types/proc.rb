module Steep
  module AST
    module Types
      class Proc
        attr_reader :location
        attr_reader :type
        attr_reader :block

        def initialize(type:, block:, location: type.location)
          @type = type
          @block = block
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) && other.type == type && other.block == block
        end

        def hash
          self.class.hash ^ type.hash ^ block.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(
            type: type.subst(s),
            block: block&.subst(s),
            location: location
          )
        end

        def to_s
          if block
            "^#{type.params} #{block} -> #{type.return_type}"
          else
            "^#{type.params} -> #{type.return_type}"
          end
        end

        def free_variables()
          @fvs ||= Set[].tap do |fvs|
            fvs.merge(type.free_variables)
            fvs.merge(block.free_variables) if block
          end
        end

        include Helper::ChildrenLevel

        def level
          children = type.params.each_type.to_a + [type.return_type]
          if block
            children.push(*block.type.params.each_type.to_a)
            children.push(block.type.return_type)
          end
          [0] + level_of_children(children)
        end

        def closed?
          type.closed? && (block.nil? || block.closed?)
        end

        def with_location(new_location)
          self.class.new(location: new_location, block: block, type: type)
        end

        def map_type(&block)
          self.class.new(
            type: type.map_type(&block),
            block: self.block&.map_type(&block),
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

        def block_required?
          block && !block.optional?
        end

        def each_child(&block)
          if block_given?
            type.each_child(&block)
            self.block&.type&.each_child(&block)
          else
            enum_for :each_child
          end
        end
      end
    end
  end
end
