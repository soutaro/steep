module Steep
  module Postconditions
    # Walks the typed AST of a Ruby source and proposes
    # `unconditional.ivars` postcondition entries for methods that assign
    # an instance variable to a type strictly narrower than the variable's
    # RBS declaration.
    #
    # Symmetric to `Steep::Contracts::Inferrer` (preconditions). Where
    # the contracts inferrer reads diagnostic output to surface required
    # callsite checks, the postcondition inferrer reads the method body
    # itself and surfaces side effects that refine the caller's view.
    #
    # MVP heuristic:
    #
    #   - Walk every `:def` inside a class/module body.
    #   - For each def, collect all `:ivasgn` nodes in the body. If an
    #     ivar is assigned more than once, the LAST write wins (linear
    #     flow assumption; conditional assigns are handled conservatively
    #     by relying on Steep's own type at the assignment node).
    #   - For each ivar, look up the *declared* type in the class's RBS
    #     definition. If the RHS type is a strict subtype, emit the
    #     refinement.
    #   - Methods whose def is inside a singleton (`def self.x`) emit a
    #     singleton entry; everything else is an instance entry.
    class Inferrer
      def self.infer(source, typing, subtyping)
        new(source, typing, subtyping).infer
      end

      def initialize(source, typing, subtyping)
        @source = source
        @typing = typing
        @subtyping = subtyping
        @factory = subtyping.factory
        @definition_builder = subtyping.factory.definition_builder
      end

      def infer
        return [] unless @source.node

        results = []
        walk_classes(@source.node, nesting: []) do |def_node, class_name, singleton|
          ivars = collect_ivar_refinements(def_node, class_name, singleton: singleton)
          next if ivars.empty?

          method_name = def_node.children[0]
          results << InferredEntry.new(
            class_name: class_name,
            method_name: method_name,
            singleton: singleton,
            ivars: ivars,
            self_type_string: marker_self_type_for(class_name, method_name, singleton: singleton)
          )
        end
        results
      end

      private

      # Composes the `unconditional.self:` value for an inferred entry,
      # following the `MarkerNaming` convention shared with rbs_infer.
      # Instance methods get `"::ClassName & ::ClassName::AfterMethod"`
      # so consumers (`apply_unconditional_postconditions`) can REPLACE
      # the receiver's type with the intersection. Singleton methods
      # don't get a marker — there's no established convention for
      # narrowing a class/module value, and the inferrer for those is
      # rare in practice. Method names that strip to empty under
      # `pascal_case` (e.g. `:"="`) are also skipped.
      def marker_self_type_for(class_name, method_name, singleton:)
        return nil if singleton
        return nil unless MarkerNaming.valid_method_name?(method_name)
        MarkerNaming.narrowed_self_type_for(class_name, method_name)
      end

      # Walks the AST yielding (def_node, class_name, singleton?) for each
      # method definition found inside a class/module. Skips top-level
      # `def`s (no class to attach a postcondition to).
      def walk_classes(node, nesting:, &block)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class
          const_node, _super, body = node.children
          name = extract_const_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk_classes(body, nesting: new_nesting, &block) if body
        when :module
          const_node, body = node.children
          name = extract_const_name(const_node)
          new_nesting = name ? nesting + [name] : nesting
          walk_classes(body, nesting: new_nesting, &block) if body
        when :def
          yield node, nesting.join("::"), false unless nesting.empty?
        when :defs
          receiver, _name, _args, _body = node.children
          if receiver&.type == :self && !nesting.empty?
            # Reshape `(:defs (self) name args body)` as `(:def name args body)`
            # so downstream code can read children[0] uniformly.
            shaped = node.updated(:def, node.children.drop(1))
            yield shaped, nesting.join("::"), true
          end
        when :begin, :kwbegin
          node.children.each { |child| walk_classes(child, nesting: nesting, &block) }
        when :sclass
          # `class << self`: the body's `def x` is a singleton method on
          # the surrounding constant. Recurse with a flag.
          body = node.children[1]
          walk_singleton_body(body, nesting: nesting, &block) if body
        else
          node.children.each do |child|
            walk_classes(child, nesting: nesting, &block) if child.is_a?(Parser::AST::Node)
          end
        end
      end

      def walk_singleton_body(node, nesting:, &block)
        return unless node.is_a?(Parser::AST::Node)
        case node.type
        when :def
          yield node, nesting.join("::"), true unless nesting.empty?
        when :begin, :kwbegin
          node.children.each { |child| walk_singleton_body(child, nesting: nesting, &block) }
        end
      end

      def extract_const_name(node)
        return nil unless node.is_a?(Parser::AST::Node)
        case node.type
        when :const
          parent, name = node.children
          parent_name = parent ? extract_const_name(parent) : nil
          parent_name ? "#{parent_name}::#{name}" : name.to_s
        end
      end

      # Returns `Hash[Symbol, AST::Types::t]` of `@ivar` to refined type,
      # populated only for ivars whose RHS type at the last assignment in
      # the body is a strict subtype of their RBS declaration.
      def collect_ivar_refinements(def_node, class_name, singleton:)
        body = def_node.children[2]
        return {} unless body

        last_writes = {} #: Hash[Symbol, AST::Types::t]
        walk_ivasgns(body) do |ivasgn_node|
          name = ivasgn_node.children[0]
          rhs_node = ivasgn_node.children[1]
          next unless rhs_node
          rhs_type = type_of(rhs_node)
          next unless rhs_type
          last_writes[name] = rhs_type
        end
        return {} if last_writes.empty?

        declared_types = declared_ivar_types(class_name, singleton: singleton)
        last_writes.each_with_object({}) do |(name, rhs_type), result|
          declared = declared_types[name]
          next unless declared
          next unless strict_subtype?(rhs_type, declared)
          result[name] = rhs_type
        end
      end

      # Recursively walks `node` yielding every `:ivasgn` descendant.
      def walk_ivasgns(node, &block)
        return unless node.is_a?(Parser::AST::Node)
        yield node if node.type == :ivasgn
        node.children.each do |child|
          walk_ivasgns(child, &block) if child.is_a?(Parser::AST::Node)
        end
      end

      def type_of(node)
        @typing.type_of(node: node)
      rescue Typing::UnknownNodeError
        nil
      end

      def declared_ivar_types(class_name, singleton:)
        return {} if class_name.empty?
        type_name = RBS::TypeName.parse("::#{class_name}").absolute!
        definition =
          if singleton
            @definition_builder.build_singleton(type_name) rescue nil
          else
            @definition_builder.build_instance(type_name) rescue nil
          end
        return {} unless definition
        definition.instance_variables.transform_values do |ivar|
          @factory.type(ivar.type)
        end
      end

      # Strict subtype check: `sub_type <: super_type` and the two are
      # not structurally equal. Equality short-circuits the subtype call
      # for the common case of `@x = same_type_method` (no refinement
      # opportunity).
      def strict_subtype?(sub_type, super_type)
        return false if sub_type == super_type
        @subtyping.check(
          Subtyping::Relation.new(sub_type: sub_type, super_type: super_type),
          self_type: AST::Builtin::Object.instance_type,
          instance_type: AST::Builtin::Object.instance_type,
          class_type: AST::Builtin::Object.module_type,
          constraints: Subtyping::Constraints.empty
        ).success?
      end
    end

    # Minimal value object for an inferred entry. Distinct from
    # `Postconditions::Entry` (which represents loaded YAML entries) so
    # callers can serialize the inference output without round-tripping
    # through the loader.
    class InferredEntry
      attr_reader :class_name, :method_name, :singleton, :ivars, :self_type_string

      def initialize(class_name:, method_name:, singleton:, ivars:, self_type_string: nil)
        @class_name = class_name
        @method_name = method_name
        @singleton = singleton
        @ivars = ivars
        @self_type_string = self_type_string
      end

      def ==(other)
        other.is_a?(InferredEntry) &&
          other.class_name == class_name &&
          other.method_name == method_name &&
          other.singleton == singleton &&
          other.ivars == ivars &&
          other.self_type_string == self_type_string
      end

      alias eql? ==

      def hash
        class_name.hash ^ method_name.hash ^ singleton.hash ^ ivars.hash ^ self_type_string.hash
      end
    end
  end
end
