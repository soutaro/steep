# frozen_string_literal: true

module Steep
  # Dsl
  #
  # Domain Specific Language parser
  # for the Steepfile
  class Dsl
    def initialize
      @signatures = nil
    end

    def evaluate_steepfile(contents)
      instance_eval(contents)
    end

    private

    def signatures(path)
      @signatures ||= []
      @signatures << path
    end

    def method_missing(method, _)
      raise NoMethodError, "Unknown Steep configuration '#{method}'"
    end

    def respond_to_missing?
      true
    end
  end
end
