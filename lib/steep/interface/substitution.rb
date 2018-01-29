module Steep
  module Interface
    class Substitution
      attr_reader :dictionary
      attr_reader :instance_type
      attr_reader :module_type

      def initialize(dictionary:, instance_type:, module_type:)
        @dictionary = dictionary
        @instance_type = instance_type
        @module_type = module_type
      end

      def self.empty
        new(dictionary: {}, instance_type: nil, module_type: nil)
      end

      def [](key)
        dictionary[key] or raise "Unknown variable: #{key}"
      end

      def key?(var)
        dictionary.key?(var)
      end

      def self.build(vars, types = nil, instance_type: nil, module_type: nil)
        types ||= vars.map {|var| AST::Types::Var.fresh(var) }

        raise "Invalid substitution: vars.size=#{vars.size}, types.size=#{types.size}" unless vars.size == types.size

        dic = vars.zip(types).each.with_object({}) do |(var, type), d|
          d[var] = type
        end

        new(dictionary: dic, instance_type: instance_type, module_type: module_type)
      end

      def except(vars)
        self.class.new(
          dictionary: dictionary.reject {|k, _| vars.include?(k) },
          instance_type: instance_type,
          module_type: module_type
        )
      end

      def merge!(s)
        dictionary.transform_values! {|ty| ty.subst(s) }
        dictionary.merge!(s.dictionary) do |key, a, b|
          if a == b
            a
          else
            raise "Duplicated key on merge!: #{key}, #{a}, #{b}"
          end
        end
      end

      def add!(v, ty)
        merge!(Substitution.new(dictionary: { v => ty }, instance_type: nil, module_type: nil))
      end
    end
  end
end
