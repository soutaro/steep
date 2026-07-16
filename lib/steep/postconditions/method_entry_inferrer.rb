module Steep
  module Postconditions
    # felixefelip/steep#68 item 4. Reads the generated controller runners
    # (`__rbs_infer__run_<action>`) and recovers, for each, the ordered list of
    # handler/action methods the request flow invokes:
    #
    #   def __rbs_infer__run_index
    #     authenticate_user
    #     return if performed?
    #     log_user_author_name if current_user_present?
    #     return if performed?
    #     index
    #   end
    #
    #   => [authenticate_user, log_user_author_name, index]   (owners resolved)
    #
    # The Runner turns each sequence into method-entry facts: a method M running
    # after a guard G (past G's halt check, which the runner always emits)
    # executes only if G did NOT halt, so G's proven-on-the-unhalted-exit facts
    # hold UNCONDITIONALLY at M's entry. That is what lets a `Current.user`
    # (or `current_user`) read inside M's own body narrow — the cross-method
    # delivery items 1-3 stop short of.
    #
    # This replaces the AST-scanned `.steep_callbacks.yml`: "runs_before" comes
    # from the pseudo-code the checker reads, not a hand-derived sidecar.
    class MethodEntryInferrer
      RUNNER_PREFIX = "__rbs_infer__run_".freeze
      HALT_CHECK = :performed?

      # One runner's flow: `calls` is `[{ class_name:, method_name: }]` in run
      # order, owners resolved from the typed call so an inherited handler
      # (`authenticate_user` on ApplicationController) resolves to its definer.
      RunnerSequence = Struct.new(:calls, keyword_init: true)

      def self.sequences(source, typing)
        new(source, typing).sequences
      end

      def initialize(source, typing)
        @source = source
        @typing = typing
      end

      def sequences
        return [] unless @source.node

        result = [] #: Array[RunnerSequence]
        each_runner_def(@source.node) do |def_node|
          calls = runner_calls(def_node)
          result << RunnerSequence.new(calls: calls) unless calls.empty?
        end
        result
      end

      private

      def each_runner_def(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        if node.type == :def && node.children[0].to_s.start_with?(RUNNER_PREFIX)
          yield node
          return
        end

        node.children.each { |c| each_runner_def(c, &block) if c.is_a?(Parser::AST::Node) }
      end

      # The handler/action calls of a runner body, in order — skipping the
      # `return if performed?` halt checks.
      def runner_calls(def_node)
        body = def_node.children[2]
        return [] unless body

        statements(body).filter_map { |stmt| handler_call(stmt) }.map do |call_node|
          resolve_owner(call_node)
        end.compact
      end

      # The handler/action call a runner statement invokes, or nil. Handles the
      # bare `authenticate_user` and the conditional `log_... if cond` forms;
      # returns nil for a `return if performed?` halt check.
      def handler_call(stmt)
        case stmt.type
        when :send
          self_call?(stmt) ? stmt : nil
        when :if
          cond, then_clause, _else = stmt.children
          # `return if performed?` — a halt check, not a handler.
          return nil if then_clause&.type == :return
          # `handler if cond` — the then-clause is the handler; the cond is a
          # predicate (`current_user_present?`, `__rbs_infer__unknown_condition?`).
          then_clause if then_clause && self_call?(then_clause)
        end
      end

      def self_call?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send &&
          (node.children[0].nil? || node.children[0].type == :self) &&
          node.children[1] != HALT_CHECK
      end

      def resolve_owner(call_node)
        call = @typing.call_of(node: call_node) rescue (return nil)
        return nil unless call.is_a?(TypeInference::MethodCall::Typed)

        decl = call.method_decls.find { |d| d.method_name.respond_to?(:type_name) }
        return nil unless decl

        {
          class_name: decl.method_name.type_name.to_s.sub(/\A::/, ""),
          method_name: call_node.children[1]
        }
      end

      def statements(body)
        body.type == :begin ? body.children : [body]
      end
    end
  end
end
