module Steep
  module Names
    class Base
      attr_reader :namespace
      attr_reader :name
      attr_reader :location

      def initialize(namespace:, name:, location: nil)
        @namespace = namespace
        @name = name
        @location = location
      end

      def absolute?
        namespace.absolute?
      end

      def relative?
        !absolute?
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name && other.namespace == namespace
      end

      def hash
        self.class.hash ^ name.hash ^ namespace.hash
      end

      alias eql? ==

      def self.parse(string)
        namespace = AST::Namespace.parse(string.to_s)
        *_, name = namespace.path
        new(namespace: namespace.parent, name: name)
      end

      def absolute!
        self.class.new(namespace: namespace.absolute!,
                       name: name)
      end

      def in_namespace(namespace)
        if absolute?
          self
        else
          self.class.new(namespace: namespace + self.namespace, name: name)
        end
      end

      def to_s
        "#{namespace}#{name}"
      end
    end

    class Module < Base
      def self.from_node(node)
        case node.type
        when :const, :casgn
          namespace = namespace_from_node(node.children[0]) or return
          name = node.children[1]
          new(namespace: namespace, name: name)
        end
      end

      def self.namespace_from_node(node)
        case node&.type
        when nil
          AST::Namespace.empty
        when :cbase
          AST::Namespace.root
        when :const
          namespace_from_node(node.children[0])&.yield_self do |parent|
            parent.append(node.children[1])
          end
        end
      end
    end

    class Interface < Base
    end

    class Alias < Base
    end
  end
end
