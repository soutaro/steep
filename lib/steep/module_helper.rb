module Steep
  module ModuleHelper
    def module_name_from_node(node)
      case node.type
      when :const, :casgn
        namespace = namespace_from_node(node.children[0]) or return
        name = node.children[1]
        RBS::TypeName.new(name: name, namespace: namespace)
      end
    end

    def namespace_from_node(node)
      case node&.type
      when nil
        RBS::Namespace.empty
      when :cbase
        RBS::Namespace.root
      when :const
        namespace_from_node(node.children[0])&.yield_self do |parent|
          parent.append(node.children[1])
        end
      end
    end
  end
end
