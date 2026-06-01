require_relative "test_helper"

class DiagnosticRubyTest < Minitest::Test
  Ruby = Steep::Diagnostic::Ruby

  # Synthetic AST nodes (e.g. the send nodes the delegation-inline path builds
  # in TypeConstruction#try_delegation_inline) have no `.loc`. Building a
  # NoMethod diagnostic for such a node must not raise — it used to call
  # `node.loc.expression` on a nil loc, crashing and flooding the logs with
  # FATAL backtraces during the contracts passes.
  def test_no_method_tolerates_send_node_without_location
    node = Parser::AST::Node.new(:send, [Parser::AST::Node.new(:ivar, [:@x]), :missing])
    assert_nil node.loc, "precondition: synthetic node has no location"

    diagnostic = Ruby::NoMethod.new(
      node: node,
      method: :missing,
      type: Steep::AST::Builtin.any_type
    )

    assert_nil diagnostic.location
    assert_equal :missing, diagnostic.method
    assert_equal node, diagnostic.node
  end
end
