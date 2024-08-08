module Steep
  class LocatedValue
    attr_reader :value, :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def ==(other)
      other.is_a?(LocatedValue) && other.value == value
    end

    alias eql? ==

    def hash
      value.hash # steep:ignore NoMethod
    end
  end
end
