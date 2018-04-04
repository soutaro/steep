module Steep
  module AST
    module Types
      module Helper
        module ChildrenLevel
          def level_of_children(children)
            children.map(&:level).inject() do |a, b|
              a.zip(b).map do |(x, y)|
                if x && y
                  x + y
                else
                  x || y || 0
                end
              end
            end || []
          end
        end
      end
    end
  end
end
