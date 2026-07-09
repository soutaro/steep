module Steep
  module Postconditions
    # Infers the return-value establishment postcondition
    # (felixefelip/steep#56): the attributes a factory-shaped method
    # guarantees non-nil on the value it returns.
    #
    # Detects the shape:
    #
    #     record = Klass.new
    #     record.attr = <non-nil>    # attribute write on a local
    #     record                     # …that local is the return value
    #
    # For each `<local>.attr = rhs` whose `rhs` is a strict subtype of the
    # attribute's declared (nilable) read type — the same strict narrowing
    # test the ivar path uses — `attr` is established. The LAST write per
    # attribute wins (linear-flow assumption, matching
    # `Inferrer#collect_ivar_refinements`).
    #
    # Only the local that is syntactically the method's last expression is
    # considered — a write to some OTHER local doesn't reach the return
    # value, so it must not leak into the postcondition.
    class ReturnEstablishmentInferrer
      include TypedNodeUtils
      include NodeHelper

      def initialize(typing, subtyping)
        @typing = typing
        @subtyping = subtyping
        @factory = subtyping.factory
        @definition_builder = subtyping.factory.definition_builder
      end

      # Returns `Array[Symbol]` of attribute names `def_node` establishes
      # non-nil on its returned value.
      def establishments(def_node)
        body = def_node.children[2]
        return [] unless body
        last_expr = last_expression(body)
        return [] unless last_expr.is_a?(Parser::AST::Node) && last_expr.type == :lvar

        returned_name = last_expr.children[0]
        returned_type = type_of(last_expr)
        return [] unless returned_type

        last_writes = {} #: Hash[Symbol, AST::Types::t]
        walk_attr_writes(body, returned_name) do |attr, rhs_node|
          rhs_type = intrinsic_type_of(rhs_node)
          next unless rhs_type
          last_writes[attr] = rhs_type
        end
        return [] if last_writes.empty?

        last_writes.filter_map do |attr, rhs_type|
          declared = declared_attr_read_type(returned_type, attr)
          next unless declared
          next unless strict_subtype?(rhs_type, declared)
          attr
        end
      end

      private

      # Yields `(attr_name_symbol, rhs_node)` for every `<lvar
      # target_name>.attr = rhs` assignment reachable in `node`. Only
      # plain attribute writes count — `[]=`, `==` and op-asgns
      # (`+=`, which parse as `:op_asgn`, not `:send`) are excluded.
      # `node` here is always a multi-statement `:begin` body (the caller
      # bails unless the return value is a bare local), so the writes are
      # descendants — `NodeHelper#each_descendant_node` does the walk.
      def walk_attr_writes(node, target_name)
        each_descendant_node(node) do |descendant|
          next unless descendant.type == :send
          receiver, method_name, *args = descendant.children
          next unless receiver.is_a?(Parser::AST::Node) &&
                      receiver.type == :lvar && receiver.children[0] == target_name
          name = method_name.to_s
          next unless name.end_with?("=") && name != "==" && name != "[]=" && (rhs = args.last)
          attr = name.delete_suffix("=")
          yield attr.to_sym, rhs unless attr.empty?
        end
      end

      # Declared read type of `attr` on `type` (the returned local's
      # type). Returns the AST type of the getter's return, or `nil` when
      # the type isn't a resolvable class instance or has no such getter.
      def declared_attr_read_type(type, attr)
        return nil unless type.is_a?(AST::Types::Name::Instance)
        definition = @definition_builder.build_instance(type.name) rescue nil
        return nil unless definition
        method = definition.methods[attr]
        return nil unless method
        method_type = method.method_types.first
        return nil unless method_type
        @factory.type(method_type.type.return_type) rescue nil
      end
    end
  end
end
