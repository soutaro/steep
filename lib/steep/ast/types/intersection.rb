module Steep
  module AST
    module Types
      class Intersection
        attr_reader :types

        def initialize(types:)
          @types = types
        end

        def self.build(types:)
          types.flat_map do |type|
            if type.is_a?(Intersection)
              type.types
            else
              [type]
            end
          end.map do |type|
            case type
            when AST::Types::Any
              return AST::Types::Any.instance()
            when AST::Types::Bot
              return AST::Types::Bot.instance
            when AST::Types::Top
              nil
            else
              type
            end
          end.compact.yield_self do |tys|
            dups = Set.new(tys)

            case dups.size
            when 0
              AST::Types::Top.instance
            when 1
              tys.first || raise
            else
              new(types: dups.to_a)
            end
          end
        end

        def ==(other)
          other.is_a?(Intersection) && other.types == types
        end

        def hash
          @hash ||= self.class.hash ^ types.hash
        end

        alias eql? ==

        def subst(s)
          self.class.build(types: types.map {|ty| ty.subst(s) })
        end

        def to_s
          "(#{types.map(&:to_s).join(" & ")})"
        end

        def free_variables()
          @fvs ||= begin
                     set = Set.new
                     types.each do |type|
                       set.merge(type.free_variables)
                     end
                     set
                   end
        end

        include Helper::ChildrenLevel

        def each_child(&block)
          if block
            types.each(&block)
          else
            types.each
          end
        end

        def map_type(&block)
          self.class.build(
            types: each_child.map(&block)
          )
        end

        def level
          [0] + level_of_children(types)
        end
      end
    end
  end
end
