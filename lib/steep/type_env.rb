module Steep
  class TypeEnv
    attr_reader :env

    def initialize(env:)
      @env = env
    end

    def self.from_annotations(annotation, env:)
      self.new(env: env).tap do |type_env|
        annotation.each do |a|
          if a.is_a?(Annotation::VarType)
            type_env.add(a.var, a.type)
          end
        end
      end
    end

    def add(name, type)
      env[name] = type
      type
    end

    def lookup(name)
      env[name]
    end
  end
end
