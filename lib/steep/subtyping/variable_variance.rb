module Steep
  module Subtyping
    class VariableVariance
      attr_reader :covariants
      attr_reader :contravariants

      def initialize(covariants:, contravariants:)
        @covariants = covariants
        @contravariants = contravariants
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

      def self.from_type(type)
        covariants = Set.new
        contravariants = Set.new

        add_type(type, variance: :covariant, covariants: covariants, contravariants: contravariants)

        new(covariants: covariants, contravariants: contravariants)
      end

      def self.from_method_type(method_type)
        covariants = Set.new
        contravariants = Set.new

        add_params(method_type.type.params, block: false, contravariants: contravariants, covariants: covariants)
        add_type(method_type.type.return_type, variance: :covariant, covariants: covariants, contravariants: contravariants)

        method_type.block&.type&.yield_self do |proc|
          add_params(proc.params, block: true, contravariants: contravariants, covariants: covariants)
          add_type(proc.return_type, variance: :contravariant, covariants: covariants, contravariants: contravariants)
        end

        new(covariants: covariants, contravariants: contravariants)
      end

      def self.add_params(params, block:, covariants:, contravariants:)
        params.each_type do |type|
          add_type(type, variance: block ? :contravariant : :covariant, covariants: covariants, contravariants: contravariants)
        end
      end

      def self.add_type(type, variance:, covariants:, contravariants:)
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
            add_type(type, variance: variance, covariants: contravariants, contravariants: covariants)
          end
          add_type(type.type.return_type, variance: variance, covariants: covariants, contravariants: contravariants)
          if type.block
            type.block.type.params.each_type do |type|
              add_type(type, variance: variance, covariants: covariants, contravariants: contravariants)
            end
            add_type(type.type.return_type, variance: variance, covariants: contravariants, contravariants: covariants)
          end
        when AST::Types::Union, AST::Types::Intersection, AST::Types::Tuple
          type.types.each do |ty|
            add_type(ty, variance: variance, covariants: covariants, contravariants: contravariants)
          end
        when AST::Types::Name::Interface, AST::Types::Name::Instance, AST::Types::Name::Alias
          type.args.each do |arg|
            add_type(arg, variance: :invariant, covariants: covariants, contravariants: contravariants)
          end
        end
      end
    end
  end
end
