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
          if types.size == 1
            return types.first || raise
          end

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
              tys.first || raise
            else
              new(types: tys, location: location)
            end
          end
        end

        def ==(other)
          other.is_a?(Union) &&
            Set.new(other.types) == Set.new(types)
        end

        def hash
          @hash ||= types.inject(self.class.hash) {|c, type| type.hash ^ c } #$ Integer
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

        def each_child(&block)
          if block
            types.each(&block)
          else
            types.each
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
