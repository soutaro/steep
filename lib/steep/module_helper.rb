module Steep
  module ModuleHelper
    def module_name_from_node(parent_node, constant_name)
      if namespace = namespace_from_node(parent_node)
        RBS::TypeName.new(name: constant_name, namespace: namespace)
      end
    end

    def namespace_from_node(node)
      if node
        case node.type
        when :cbase
          RBS::Namespace.root
        when :const
          if parent = namespace_from_node(node.children[0])
            parent.append(node.children[1])
          end
        end
      else
        RBS::Namespace.empty
      end
    end
  end
end
