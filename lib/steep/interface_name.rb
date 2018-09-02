module Steep
  class InterfaceName
    attr_reader :name

    def initialize(name:)
      @name = name
    end

    def ==(other)
      other.is_a?(InterfaceName) && other.name == name
    end

    def hash
      self.class.hash ^ name.hash
    end

    alias eql? ==

    def to_s
      name.to_s
    end
  end
end
