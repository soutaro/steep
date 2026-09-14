module Steep
  module AST
    module Types
      class Union
        attr_reader :types

        def initialize(types:)
          @types = types
        end

        def self.build(types:)
          return AST::Types::Bot.instance if types.empty?
          if types.size == 1
            return types.first || raise
          end

          # A union among the types is the exception, while `flat_map` allocates a singleton
          # array for every type that is not one
          if types.any? {|type| type.is_a?(Union) }
            types = types.flat_map do |type|
              if type.is_a?(Union)
                type.types
              else
                [type]
              end
            end
          end

          tys = [] #: Array[t]

          types.each do |type|
            case type
            when AST::Types::Any
              return AST::Types::Any.instance()
            when AST::Types::Top
              return AST::Types::Top.instance
            when AST::Types::Bot
              # `bot` adds nothing to a union
            else
              tys << type
            end
          end

          tys.uniq!

          case tys.size
          when 0
            AST::Types::Bot.instance
          when 1
            tys.first || raise
          else
            new(types: tys)
          end
        end

        def ==(other)
          return true if equal?(other)
          return false unless other.is_a?(Union)

          # The order of the types doesn't matter, but two equal unions are usually built the
          # same way, and the sets are allocated only when they are not
          return true if other.types == types

          Set.new(other.types) == Set.new(types)
        end

        def hash
          @hash ||= types.inject(self.class.hash) {|c, type| type.hash ^ c } #$ Integer
        end

        alias eql? ==

        def subst(s)
          self.class.build(types: types.map {|ty| ty.subst(s) })
        end

        def to_s
          "(#{types.map(&:to_s).join(" | ")})"
        end

        def free_variables
          @fvs ||= Set.new.tap do |set|
            types.each do |type|
              set.merge(type.free_variables)
            end
          end
        end

        def each_child(&block)
          if block
            types.each(&block)
          else
            types.each
          end
        end

        def map_type(&block)
          Union.build(types: types.map(&block))
        end

        include Helper::ChildrenLevel

        def level
          [0] + level_of_children(types)
        end

        def with_location(new_location)
          self.class.new(types: types)
        end
      end
    end
  end
end
