module Steep
  module AST
    module Types
      module Helper
        module ChildrenLevel
          def level_of_children(children)
            children.map(&:level).sort {|a, b| b.size <=> a.size }.inject() do |a, b|
              a.zip(b).map do |(x, y)|
                if x && y
                  x + y
                else
                  x || y
                end
              end
            end || []
          end
        end

        module NoFreeVariables
          def free_variables()
            @fvs ||= Set.new
          end
        end

        module NoChild
          def each_child(&block)
            unless block
              enum_for :each_child
            end
          end
        end
      end
    end
  end
end
