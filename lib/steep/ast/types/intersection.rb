module Steep
  module AST
    module Types
      class Intersection
        attr_reader :types
        attr_reader :location

        def initialize(types:, location: nil)
          @types = types
          @location = location
        end

        def self.build(types:, location: nil)
          types.flat_map do |type|
            if type.is_a?(Intersection)
              type.types
            else
              [type]
            end
          end.map do |type|
            case type
            when AST::Types::Any
              return AST::Types::Any.new(location: location)
            when AST::Types::Bot
              return AST::Types::Bot.new(location: location)
            when AST::Types::Top
              nil
            else
              type
            end
          end.compact.yield_self do |tys|
            dups = Set.new(tys)

            case dups.size
            when 0
              AST::Types::Top.new(location: location)
            when 1
              tys.first || raise
            else
              new(types: dups.to_a, location: location)
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
          self.class.build(location: location, types: types.map {|ty| ty.subst(s) })
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

        def level
          [0] + level_of_children(types)
        end

        def with_location(new_location)
          self.class.new(types: types, location: new_location)
        end
      end
    end
  end
end
