module Steep
  module AST
    module Types
      class Union
        attr_reader :types
        attr_reader :location

        def initialize(types:, location: nil)
          @types = types
          @location = location
        end

        def self.build(types:, location: nil)
          return AST::Types::Bot.new if types.empty?
          return types.first if types.size == 1

          types.flat_map do |type|
            if type.is_a?(Union)
              type.types
            else
              [type]
            end
          end.map do |type|
            case type
            when AST::Types::Any
              return AST::Types::Any.new(location: location)
            when AST::Types::Top
              return AST::Types::Top.new(location: location)
            when AST::Types::Bot
              nil
            else
              type
            end
          end.compact.uniq.yield_self do |tys|
            case tys.size
            when 0
              AST::Types::Bot.new
            when 1
              tys.first
            else
              new(types: tys, location: location)
            end
          end
        end

        def ==(other)
          other.is_a?(Union) &&
           other.types.all? do |typ1|
            types.any? { |typ2| typ1 == typ2 }
           end
        end

        def hash
          @hash ||= self.class.hash ^ types.sort_by(&:to_s).hash
        end

        alias eql? ==

        def subst(s)
          self.class.build(location: location, types: types.map {|ty| ty.subst(s) })
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

        include Helper::ChildrenLevel

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
