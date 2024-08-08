module Steep
  module AST
    module Types
      module SharedInstance
        def instance
          @instance ||= new
        end
      end
    end
  end
end
