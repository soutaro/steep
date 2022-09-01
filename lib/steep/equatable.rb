module Steep
  module Equatable
    def ==(other)
      if other.class == self.class
        instance_variables.all? do |name|
          other.instance_variable_get(name) == instance_variable_get(name)
        end
      else
        false
      end
    end

    def eql?(other)
      self == other
    end

    def hash
      instance_variables.inject(self.class.hash) do |hash, name|
        hash ^ instance_variable_get(name).hash
      end
    end
  end
end
