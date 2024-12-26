module Steep
  module Interface
    class TypeParam
      attr_reader :name
      attr_reader :upper_bound
      attr_reader :variance
      attr_reader :unchecked
      attr_reader :location
      attr_reader :default_type

      def initialize(name:, upper_bound:, variance:, unchecked:, location: nil, default_type:)
        @name = name
        @upper_bound = upper_bound
        @variance = variance
        @unchecked = unchecked
        @location = location
        @default_type = default_type
      end

      def ==(other)
        other.is_a?(TypeParam) &&
          other.name == name &&
          other.upper_bound == upper_bound &&
          other.variance == variance &&
          other.unchecked == unchecked &&
          other.default_type == default_type
      end

      alias eql? ==

      def hash
        name.hash ^ upper_bound.hash ^ variance.hash ^ unchecked.hash ^ default_type.hash
      end

      def self.rename(params, conflicting_names = params.map(&:name), new_names = conflicting_names.map {|n| AST::Types::Var.fresh_name(n) })
        unless conflicting_names.empty?
          hash = conflicting_names.zip(new_names).to_h
          new_types = new_names.map {|n| AST::Types::Var.new(name: n) }

          subst = Substitution.build(conflicting_names, new_types)

          [
            params.map do |param|
              if hash.key?(param.name) || param.upper_bound
                TypeParam.new(
                  name: hash[param.name] || param.name,
                  upper_bound: param.upper_bound&.subst(subst),
                  variance: param.variance,
                  unchecked: param.unchecked,
                  location: param.location,
                  default_type: param.default_type&.subst(subst)
                )
              else
                param
              end
            end,
            subst
          ]
        else
          [params, Substitution.empty]
        end
      end

      def to_s
        buf = +""

        if unchecked
          buf << "unchecked "
        end

        case variance
        when :covariant
          buf << "out "
        when :contravariant
          buf << "in "
        end

        buf << name.to_s

        if upper_bound
          buf << " < #{upper_bound}"
        end

        buf
      end

      def update(name: self.name, upper_bound: self.upper_bound, variance: self.variance, unchecked: self.unchecked, location: self.location, default_type: self.default_type)
        TypeParam.new(
          name: name,
          upper_bound: upper_bound,
          variance: variance,
          unchecked: unchecked,
          location: location,
          default_type: default_type
        )
      end

      def subst(s)
        if u = upper_bound
          ub = u.subst(s)
        end

        if d = default_type
          dt = d.subst(s)
        end

        if ub || dt
          update(upper_bound: ub, default_type: dt)
        else
          self
        end
      end
    end
  end
end
