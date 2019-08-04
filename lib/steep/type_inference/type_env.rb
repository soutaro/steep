module Steep
  module TypeInference
    class TypeEnv
      attr_reader :subtyping
      attr_reader :lvar_types
      attr_reader :const_types
      attr_reader :gvar_types
      attr_reader :ivar_types
      attr_reader :const_env

      def initialize(subtyping:, const_env:)
        @subtyping = subtyping
        @lvar_types = {}
        @const_types = {}
        @gvar_types = {}
        @ivar_types = {}
        @const_env = const_env
      end

      def initialize_copy(other)
        @subtyping = other.subtyping
        @lvar_types = other.lvar_types.dup
        @const_types = other.const_types.dup
        @gvar_types = other.gvar_types.dup
        @ivar_types = other.ivar_types.dup
        @const_env = other.const_env
      end

      def self.build(annotations:, signatures:, subtyping:, const_env:)
        new(subtyping: subtyping, const_env: const_env).tap do |env|
          annotations.lvar_types.each do |name, type|
            env.set(lvar: name, type: type)
          end
          annotations.ivar_types.each do |name, type|
            env.set(ivar: name, type: type)
          end
          annotations.const_types.each do |name, type|
            env.set(const: name, type: type)
          end
          signatures.name_to_global.each do |name, global|
            type = signatures.absolute_type(global.type, namespace: Ruby::Signature::Namespace.root) {|ty| ty.name.absolute! }
            env.set(gvar: name, type: subtyping.factory.type(type))
          end
        end
      end

      def with_annotations(lvar_types: {}, ivar_types: {}, const_types: {}, gvar_types: {}, &block)
        dup.tap do |env|
          merge!(original_env: env.lvar_types, override_env: lvar_types, &block)
          merge!(original_env: env.ivar_types, override_env: ivar_types, &block)
          merge!(original_env: env.gvar_types, override_env: gvar_types, &block)

          const_types.each do |name, annotated_type|
            original_type = self.const_types[name] || const_env.lookup(name)
            if original_type
              assert_annotation name, original_type: original_type, annotated_type: annotated_type, &block
            end
            env.const_types[name] = annotated_type
          end
        end
      end

      def join!(envs)
        lvars = {}

        common_vars = envs.map {|env| Set.new(env.lvar_types.keys) }.inject {|a, b| a & b }

        envs.each do |env|
          env.lvar_types.each do |name, type|
            unless lvar_types.key?(name)
              lvars[name] = [] unless lvars[name]
              lvars[name] << type
            end
          end
        end

        lvars.each do |name, types|
          if lvar_types.key?(name) || common_vars.member?(name)
            set(lvar: name, type: AST::Types::Union.build(types: types))
          else
            set(lvar: name, type: AST::Types::Union.build(types: types + [AST::Types::Nil.new]))
          end
        end
      end

      # @type method assert: (const: Names::Module) { () -> void } -> AST::Type
      #                    | (gvar: Symbol) { () -> void } -> AST::Type
      #                    | (ivar: Symbol) { () -> void } -> AST::Type
      #                    | (lvar: Symbol) { () -> AST::Type | nil } -> AST::Type
      def get(lvar: nil, const: nil, gvar: nil, ivar: nil)
        case
        when lvar
          lvar_name(lvar).yield_self do |name|
            if lvar_types.key?(name)
              lvar_types[name]
            else
              ty = yield
              lvar_types[name] = ty || AST::Types::Any.new
            end
          end
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

      def set(lvar: nil, const: nil, gvar: nil, ivar: nil, type:)
        case
        when lvar
          lvar_name(lvar).yield_self do |name|
            lvar_types[name] = type
          end
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
      #                    | (lvar: Symbol | LabeledName, type: AST::Type) { (Subtyping::Result::Failure) -> void } -> AST::Type
      def assign(lvar: nil, const: nil, gvar: nil, ivar: nil, type:, &block)
        case
        when lvar
          yield_self do
            name = lvar_name(lvar)
            var_type = lvar_types[name]
            if var_type
              assert_assign(var_type: var_type, lhs_type: type, &block)
            else
              lvar_types[name] = type
            end
          end
        when const
          yield_self do
            const_type = const_types[const] || const_env.lookup(const)
            if const_type
              assert_assign(var_type: const_type, lhs_type: type, &block)
            else
              yield nil
              AST::Types::Any.new
            end
          end
        else
          lookup_dictionary(ivar: ivar, gvar: gvar) do |var_name, dictionary|
            if dictionary.key?(var_name)
              assert_assign(var_type: dictionary[var_name], lhs_type: type, &block)
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

      def lvar_name(lvar)
        case lvar
        when Symbol
          lvar
        when ASTUtils::Labeling::LabeledName
          lvar.name
        end
      end

      def assert_assign(var_type:, lhs_type:)
        var_type = subtyping.expand_alias(var_type)
        lhs_type = subtyping.expand_alias(lhs_type)

        relation = Subtyping::Relation.new(sub_type: lhs_type, super_type: var_type)
        constraints = Subtyping::Constraints.new(unknowns: Set.new)

        subtyping.check(relation, constraints: constraints).else do |result|
          yield result
        end

        var_type
      end

      def merge!(original_env:, override_env:, &block)
        original_env.merge!(override_env) do |name, original_type, override_type|
          assert_annotation name, annotated_type: override_type, original_type: original_type, &block
        end
      end

      def assert_annotation(name, annotated_type:, original_type:)
        annotated_type = subtyping.expand_alias(annotated_type)
        original_type = subtyping.expand_alias(original_type)

        relation = Subtyping::Relation.new(sub_type: annotated_type, super_type: original_type)
        constraints = Subtyping::Constraints.new(unknowns: Set.new)

        subtyping.check(relation, constraints: constraints).else do |result|
          yield name, relation, result
        end

        annotated_type
      end
    end
  end
end
