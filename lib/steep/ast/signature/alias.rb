module Steep
  module AST
    module Signature
      class Alias
        attr_reader :location
        attr_reader :name
        attr_reader :params
        attr_reader :type

        def initialize(location:, name:, params:, type:)
          @location = location
          @name = name
          @params = params
          @type = type
        end
      end
    end
  end
end
