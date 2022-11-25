module Steep
  module AST
    module Types
      class Proc
        attr_reader :location
        attr_reader :type
        attr_reader :self_type
        attr_reader :block

        def initialize(type:, block:, self_type:, location: type.location)
          @type = type
          @block = block
          @self_type = self_type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) && other.type == type && other.block == block && other.self_type == self_type
        end

        def hash
          self.class.hash ^ type.hash ^ block.hash ^ self_type.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(
            type: type.subst(s),
            block: block&.subst(s),
            self_type: self_type&.subst(s),
            location: location
          )
        end

        def to_s
          s =
            if self_type
              "[self: #{self_type}] "
            end

          if block
            "^#{type.params} #{s}#{block} -> #{type.return_type}"
          else
            "^#{type.params} #{s}-> #{type.return_type}"
          end
        end

        def free_variables()
          @fvs ||= Set[].tap do |fvs|
            fvs.merge(type.free_variables)
            fvs.merge(block.free_variables) if block
            fvs.merge(self_type.free_variables) if self_type
          end
        end

        include Helper::ChildrenLevel

        def level
          children = type.params.each_type.to_a + [type.return_type]
          if block
            children.push(*block.type.params.each_type.to_a)
            children.push(block.type.return_type)
          end
          if self_type
            children.push(self_type)
          end
          [0] + level_of_children(children)
        end

        def with_location(new_location)
          self.class.new(location: new_location, block: block, type: type, self_type: self_type)
        end

        def map_type(&block)
          self.class.new(
            type: type.map_type(&block),
            block: self.block&.map_type(&block),
            self_type: self_type ? yield(self_type) : nil,
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
          if block
            !block.optional?
          else
            false
          end
        end

        def each_child(&block)
          if block
            type.each_child(&block)
            self.block&.type&.each_child(&block)
            self_type.each_child(&block) if self_type
          else
            enum_for :each_child
          end
        end
      end
    end
  end
end
