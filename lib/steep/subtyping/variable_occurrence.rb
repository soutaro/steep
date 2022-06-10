module Steep
  module Subtyping
    class VariableOccurrence
      attr_reader :params
      attr_reader :returns

      def initialize
        @params = Set.new
        @returns = Set.new
      end

      def add_method_type(method_type)
        method_type.type.params.each_type do |type|
          each_var(type) do |var|
            params << var
          end
        end
        each_var(method_type.type.return_type) do |var|
          returns << var
        end

        method_type.block&.yield_self do |block|
          block.type.params.each_type do |type|
            each_var(type) do |var|
              params << var
            end
          end
          each_var(block.type.return_type) do |var|
            returns << var
          end
        end

        params.subtract(returns)
      end

      def each_var(type, &block)
        type.free_variables.each(&block)
      end

      def strictly_return?(var)
        !params.member?(var) && returns.member?(var)
      end

      def self.from_method_type(method_type)
        self.new.tap do |occurrence|
          occurrence.add_method_type(method_type)
        end
      end
    end
  end
end
