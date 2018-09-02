module Steep
  class AliasName
    attr_reader :name

    def initialize(name:)
      @name = name
    end

    def ==(other)
      other.is_a?(AliasName) && other.name == name
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
