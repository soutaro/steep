module Steep
  module AST
    module Signature
      class Extension
        attr_reader :location
        attr_reader :module_name
        attr_reader :name
        attr_reader :members
        attr_reader :params

        def initialize(location:, module_name:, params:, name:, members:)
          @location = location
          @module_name = module_name
          @params = params
          @name = name
          @members = members
        end
      end
    end
  end
end
