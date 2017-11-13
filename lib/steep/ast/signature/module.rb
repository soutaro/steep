module Steep
  module AST
    module Signature
      class Module
        attr_reader :location
        attr_reader :name
        attr_reader :params
        attr_reader :self_type
        attr_reader :members

        def initialize(name:, location:, params:, self_type:, members:)
          @name = name
          @location = location
          @params = params
          @self_type = self_type
          @members = members
        end
      end
    end
  end
end
