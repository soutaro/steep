module Steep
  class ModuleName
    attr_reader :name

    def initialize(name:, absolute:)
      @name = name
      @absolute = absolute
    end

    def self.parse(name)
      name = name.to_s
      new(name: name.gsub(/\A::/, ""), absolute: name.start_with?("::"))
    end

    def self.from_node(node)
      case node.type
      when :const
        relative_node = new(name: node.children.last.to_s, absolute: false)
        parent_node = node.children.first

        case parent_node&.type
        when :cbase
          relative_node.absolute!
        when nil
          relative_node
        else
          from_node(parent_node)&.yield_self do |parent|
            parent + relative_node
          end
        end
      else
        nil
      end
    end

    def ==(other)
      other.is_a?(self.class) && other.name == name && other.absolute? == absolute?
    end

    def hash
      self.class.hash ^ name.hash ^ @absolute.hash
    end

    alias eql? ==

    def absolute!
      self.class.new(name: name, absolute: true)
    end

    def absolute?
      !!@absolute
    end

    def relative?
      !absolute?
    end

    def to_s
      if absolute?
        "::#{name}"
      else
        name
      end
    end

    def +(other)
      case other
      when self.class
        if other.absolute?
          other
        else
          self.class.new(name: "#{name}::#{other.name}", absolute: absolute?)
        end
      else
        self + self.class.parse(other)
      end
    end

    def components
      name.split(/::/).map.with_index {|s, index|
        if index == 0 && absolute?
          self.class.parse(s).absolute!
        else
          self.class.parse(s)
        end
      }
    end

    def parent
      components = components()
      components.pop

      unless components.empty?
        self.class.parse(components.join("::"))
      end
    end

    def simple?
      components.size == 1
    end
  end
end
