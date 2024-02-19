module Steep
  module Subtyping
    class VariableVariance
      attr_reader :covariants
      attr_reader :contravariants
      attr_reader :env

      def initialize(env)
        @env = env
        @covariants = Set[]
        @contravariants = Set[]
      end

      def covariant?(var)
        covariants.member?(var) && !contravariants.member?(var)
      end

      def contravariant?(var)
        contravariants.member?(var) && !covariants.member?(var)
      end

      def invariant?(var)
        covariants.member?(var) && contravariants.member?(var)
      end

      def unused?(var)
        !covariants.member?(var) && !contravariants.member?(var)
      end

      def add_type(type)
        insert_type(type, :covariant)
        self
      end

      def add_method_type(type)
        type.type.params.each_type do |type|
          insert_type(type, :contravariant)
        end
        insert_type(type.type.return_type, :covariant)

        if block = type.block
          block.type.params.each_type do |type|
            insert_type(type, :covariant)
          end
          insert_type(block.type.return_type, :contravariant)

          if block.self_type
            insert_type(block.self_type, :contravariant)
          end
        end

        self
      end

      def flip(v)
        case v
        when :covariant
          :contravariant
        when :contravariant
          :covariant
        else
          v
        end
      end

      def insert_type(type, variance)
        case type
        when AST::Types::Var
          case variance
          when :covariant
            covariants << type.name
          when :contravariant
            contravariants << type.name
          when :invariant
            covariants << type.name
            contravariants << type.name
          end
        when AST::Types::Proc
          type.type.params.each_type do |type|
            insert_type(type, flip(variance))
          end
          insert_type(type.type.return_type, variance)
          if type.block
            type.block.type.params.each_type do |type|
              insert_type(type, variance)
            end
            insert_type(type.type.return_type, flip(variance))

            if type.block.self_type
              insert_type(type.block.self_type, variance)
            end
          end
        when AST::Types::Name::Interface, AST::Types::Name::Instance, AST::Types::Name::Alias
          type_name = env.normalize_type_name!(type.name)
          params =
            case
            when type_name.class?
              decl = env.normalized_module_class_entry(type_name) or raise
              decl.primary.decl.type_params
            when type_name.interface?
              decl = env.interface_decls.fetch(type_name)
              decl.decl.type_params
            when type_name.alias?
              decl = env.type_alias_decls.fetch(type_name)
              decl.decl.type_params
            else
              raise
            end

          pairs = params.zip(type.args)

          pairs.each do |param, type|
            if type
              case param.variance
              when :invariant
                insert_type(type, :invariant)
              when :covariant
                insert_type(type, variance)
              when :contravariant
                insert_type(type, flip(variance))
              end
            end
          end
        else
          type.each_child do |ty|
            insert_type(ty, variance)
          end
        end
      end
    end
  end
end
