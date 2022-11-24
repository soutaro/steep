module Steep
  module Interface
    class Substitution
      class InvalidSubstitutionError < StandardError
        attr_reader :vars_size
        attr_reader :types_size

        def initialize(vars_size:, types_size:)
          @vars_size = vars_size
          @types_size = types_size

          super "Invalid substitution: vars.size=#{vars_size}, types.size=#{types_size}"
        end
      end

      attr_reader :dictionary
      attr_reader :instance_type
      attr_reader :module_type
      attr_reader :self_type

      def initialize(dictionary:, instance_type:, module_type:, self_type:)
        @dictionary = dictionary
        @instance_type = instance_type
        @module_type = module_type
        @self_type = self_type
      end

      def self.empty
        new(dictionary: {},
            instance_type: AST::Types::Instance.instance,
            module_type: AST::Types::Class.instance,
            self_type: AST::Types::Self.instance)
      end

      def empty?
        dictionary.empty? &&
          instance_type.is_a?(AST::Types::Instance) &&
          module_type.is_a?(AST::Types::Class) &&
          self_type.is_a?(AST::Types::Self)
      end

      def domain
        set = Set.new

        set.merge(dictionary.keys)
        set << AST::Types::Self.instance if self_type
        set << AST::Types::Class.instance if module_type
        set << AST::Types::Instance.instance if instance_type

        set
      end

      def to_s
        a = [] #: Array[String]

        dictionary.each do |x, ty|
          a << "#{x} -> #{ty}"
        end

        a << "[instance_type] -> #{instance_type}"
        a << "[module_type] -> #{module_type}"
        a << "[self_type] -> #{self_type}"

        "{ #{a.join(", ")} }"
      end

      def [](key)
        dictionary[key] or raise "Unknown variable: #{key}"
      end

      def key?(var)
        dictionary.key?(var)
      end

      def apply?(type)
        case type
        when AST::Types::Var
          key?(type.name)
        when AST::Types::Self
          !self_type.is_a?(AST::Types::Self)
        when AST::Types::Instance
          !instance_type.is_a?(AST::Types::Instance)
        when AST::Types::Class
          !module_type.is_a?(AST::Types::Class)
        else
          type.each_child.any? {|t| apply?(t) }
        end
      end

      def self.build(vars, types = nil, instance_type: nil, module_type: nil, self_type: nil)
        types ||= vars.map {|var| AST::Types::Var.fresh(var) }

        raise InvalidSubstitutionError.new(vars_size: vars.size, types_size: types.size) unless vars.size == types.size

        dic = vars.zip(types).each.with_object({}) do |(var, type), d| #$ Hash[Symbol, AST::Types::t]
          type or raise
          d[var] = type
        end

        new(dictionary: dic, instance_type: instance_type, module_type: module_type, self_type: self_type)
      end

      def except(vars)
        self.class.new(
          dictionary: dictionary.dup,
          instance_type: instance_type,
          module_type: module_type,
          self_type: self_type
        ).except!(vars)
      end

      def except!(vars)
        vars.each do |var|
          dictionary.delete(var)
        end

        self
      end

      def merge!(s, overwrite: false)
        dictionary.transform_values! {|ty| ty.subst(s) }
        dictionary.merge!(s.dictionary) do |key, a, b|
          if a == b
            a
          else
            if overwrite
              b
            else
              raise "Duplicated key on merge!: #{key}, #{a}, #{b} (#{self})"
            end
          end
        end

        @instance_type = instance_type.subst(s) if instance_type
        @module_type = module_type.subst(s) if module_type
        @self_type = self_type.subst(s) if self_type

        self
      end

      def merge(s)
        Substitution.new(dictionary: dictionary.dup,
                         instance_type: instance_type,
                         module_type: module_type,
                         self_type: self_type).merge!(s)
      end

      def add!(v, ty)
        merge!(Substitution.new(dictionary: { v => ty }, instance_type: instance_type, module_type: module_type, self_type: self_type))
      end
    end
  end
end
