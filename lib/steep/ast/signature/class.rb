module Steep
  module AST
    module Signature
      class SuperClass
        attr_reader :location
        attr_reader :name
        attr_reader :args

        def initialize(name:, args:, location:)
          @name = name
          @args = args
          @location = location
        end
      end

      class Class
        attr_reader :location
        attr_reader :name
        attr_reader :params
        attr_reader :super_class
        attr_reader :members

        def initialize(name:, params:, super_class:, location:, members:)
          @name = name
          @params = params
          @super_class = super_class
          @location = location
          @members = members
        end
      end
    end
  end
end
