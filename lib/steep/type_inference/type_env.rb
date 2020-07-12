module Steep
  module TypeInference
    class TypeEnv
      attr_reader :subtyping
      attr_reader :const_types
      attr_reader :gvar_types
      attr_reader :ivar_types
      attr_reader :const_env

      def initialize(subtyping:, const_env:)
        @subtyping = subtyping
        @const_types = {}
        @gvar_types = {}
        @ivar_types = {}
        @const_env = const_env
      end

      def initialize_copy(other)
        @subtyping = other.subtyping
        @const_types = other.const_types.dup
        @gvar_types = other.gvar_types.dup
        @ivar_types = other.ivar_types.dup
        @const_env = other.const_env
      end

      def self.build(annotations:, signatures:, subtyping:, const_env:)
        new(subtyping: subtyping, const_env: const_env).tap do |env|
          annotations.ivar_types.each do |name, type|
            env.set(ivar: name, type: type)
          end
          annotations.const_types.each do |name, type|
            env.set(const: name, type: type)
          end
          signatures.global_decls.each do |name, entry|
            type = entry.decl.type
            env.set(gvar: name, type: subtyping.factory.type(type))
          end
        end
      end

      def with_annotations(ivar_types: {}, const_types: {}, gvar_types: {}, self_type:, &block)
        dup.tap do |env|
          merge!(original_env: env.ivar_types, override_env: ivar_types, self_type: self_type, &block)
          merge!(original_env: env.gvar_types, override_env: gvar_types, self_type: self_type, &block)

          const_types.each do |name, annotated_type|
            original_type = self.const_types[name] || const_env.lookup(name)
            if original_type
              assert_annotation name,
                                original_type: original_type,
                                annotated_type: annotated_type,
                                self_type: self_type,
                                &block
            end
            env.const_types[name] = annotated_type
          end
        end
      end

      # @type method assert: (const: Names::Module) { () -> void } -> AST::Type
      #                    | (gvar: Symbol) { () -> void } -> AST::Type
      #                    | (ivar: Symbol) { () -> void } -> AST::Type
      def get(const: nil, gvar: nil, ivar: nil)
        case
        when const
          if const_types.key?(const)
            const_types[const]
          else
            const_env.lookup(const).yield_self do |type|
              if type
                type
              else
                yield
                AST::Types::Any.new
              end
            end
          end
        else
          lookup_dictionary(ivar: ivar, gvar: gvar) do |var_name, dictionary|
            if dictionary.key?(var_name)
              dictionary[var_name]
            else
              yield
              AST::Types::Any.new
            end
          end
        end
      end

      def set(const: nil, gvar: nil, ivar: nil, type:)
        case
        when const
          const_types[const] = type
        else
          lookup_dictionary(ivar: ivar, gvar: gvar) do |var_name, dictionary|
            dictionary[var_name] = type
          end
        end
      end

      # @type method assign: (const: Names::Module, type: AST::Type) { (Subtyping::Result::Failure | nil) -> void } -> AST::Type
      #                    | (gvar: Symbol, type: AST::Type) { (Subtyping::Result::Failure | nil) -> void } -> AST::Type
      #                    | (ivar: Symbol, type: AST::Type) { (Subtyping::Result::Failure | nil) -> void } -> AST::Type
      def assign(const: nil, gvar: nil, ivar: nil, type:, self_type:, &block)
        case
        when const
          yield_self do
            const_type = const_types[const] || const_env.lookup(const)
            if const_type
              assert_assign(var_type: const_type, lhs_type: type, self_type: self_type, &block)
            else
              yield nil
              AST::Types::Any.new
            end
          end
        else
          lookup_dictionary(ivar: ivar, gvar: gvar) do |var_name, dictionary|
            if dictionary.key?(var_name)
              assert_assign(var_type: dictionary[var_name], lhs_type: type, self_type: self_type, &block)
            else
              yield nil
              AST::Types::Any.new
            end
          end
        end
      end

      def lookup_dictionary(ivar:, gvar:)
        case
        when ivar
          yield ivar, ivar_types
        when gvar
          yield gvar, gvar_types
        end
      end

      def assert_assign(var_type:, lhs_type:, self_type:)
        return var_type if var_type == lhs_type

        var_type = subtyping.expand_alias(var_type)
        lhs_type = subtyping.expand_alias(lhs_type)

        relation = Subtyping::Relation.new(sub_type: lhs_type, super_type: var_type)
        constraints = Subtyping::Constraints.new(unknowns: Set.new)

        subtyping.check(relation, self_type: self_type, constraints: constraints).else do |result|
          yield result
        end

        var_type
      end

      def merge!(original_env:, override_env:, self_type:, &block)
        original_env.merge!(override_env) do |name, original_type, override_type|
          assert_annotation name, annotated_type: override_type, original_type: original_type, self_type: self_type, &block
        end
      end

      def assert_annotation(name, annotated_type:, original_type:, self_type:)
        return annotated_type if annotated_type == original_type

        annotated_type = subtyping.expand_alias(annotated_type)
        original_type = subtyping.expand_alias(original_type)

        relation = Subtyping::Relation.new(sub_type: annotated_type, super_type: original_type)
        constraints = Subtyping::Constraints.new(unknowns: Set.new)

        subtyping.check(relation, constraints: constraints, self_type: self_type).else do |result|
          yield name, relation, result
        end

        annotated_type
      end
    end
  end
end
