module Steep
  module Interface
    class Interface
      class Combination
        attr_reader :operator
        attr_reader :types

        def initialize(operator:, types:)
          @types = types
          @operator = operator
        end

        def self.overload(types)
          new(operator: :overload, types: types)
        end

        def self.union(types)
          case types.size
          when 0
            raise "Combination.union called with zero types"
          when 1
            types.first
          else
            new(operator: :union, types: types)
          end
        end

        def self.intersection(types)
          case types.size
          when 0
            raise "Combination.intersection called with zero types"
          when 1
            types.first
          else
            new(operator: :intersection, types: types)
          end
        end

        def to_s
          case operator
          when :overload
            "{ #{types.map(&:to_s).join(" | ")} }"
          when :union
            "[#{types.map(&:to_s).join(" | ")}]"
          when :intersection
            "[#{types.map(&:to_s).join(" & ")}]"
          end
        end
      end

      attr_reader :type
      attr_reader :methods

      def initialize(type:, private:)
        @type = type
        @private = private
        @methods = {}
      end

      def private?
        @private
      end

      def public?
        !private?
      end
    end
  end
end
