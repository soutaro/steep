# Steep runs on Ruby 2.6 and it needs a shim of `filter_map`

module Shims
  module EnumerableFilterMap
    def filter_map(&block)
      if block
        result = []

        each do |element|
          if value = yield(element)
            result << value
          end
        end

        result
      else
        enum_for :filter_map
      end
    end
  end

  unless Enumerable.method_defined?(:filter_map)
    Enumerable.include EnumerableFilterMap

    module ::Enumerable
      alias filter_map filter_map
    end
  end
end

