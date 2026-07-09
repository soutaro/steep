require_relative "test_helper"

# End-to-end application of the return-value establishment postcondition
# (felixefelip/steep#56): at `x = build`, when `build` declares
# `unconditional.returns.establishes: [attr]`, the pure-node fact
# `x.attr` becomes non-nil — so a later `x.<contracted>` whose contract
# `requires self.attr` is satisfied, even though `attr` was written
# inside `build`, not at the call site.
class PostconditionsReturnEstablishmentTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Contracts = Steep::Contracts
  Postconditions = Steep::Postconditions
  Diagnostic = Steep::Diagnostic

  RBS = <<~RBS
    class REThing
      def self.new: () -> REThing
    end

    class RERecord
      attr_accessor thing: REThing?
      def self.new: () -> RERecord
      # `requires self.thing` (declared via the contract store below).
      def use_thing: () -> Integer
    end

    class REProxy
      def build: () -> RERecord
      def run_ok: () -> Integer
      def run_bad: () -> Integer
    end
  RBS

  # `RERecord#use_thing` requires `self.thing` be non-nil.
  def use_thing_contract
    Contracts::Store.from_hash(
      {
        "version" => 1,
        "methods" => {
          "RERecord#use_thing" => {
            "requires" => [
              { "kind" => "not_nil",
                "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "thing" } }
            ]
          }
        }
      },
      source: "<test>"
    )
  end

  # `REProxy#build` establishes `thing` on its returned record.
  def build_postcondition
    Postconditions::Store.from_hash(
      {
        "version" => 1,
        "postconditions" => [
          {
            "class" => "REProxy",
            "method" => "build",
            "unconditional" => { "returns" => { "establishes" => ["thing"] } }
          }
        ]
      },
      source: "<test>"
    )
  end

  def test_build_then_use_thing_satisfies_precondition
    with_checker(RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::REProxy
        def run_ok
          record = build
          record.use_thing
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_thing_contract, postconditions: build_postcondition) do |construction, typing|
        construction.synthesize(source.node)

        precondition_errors = typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied)
        assert_empty precondition_errors,
                     "`record = build` should import `record.thing` non-nil so `record.use_thing` is satisfied, got: #{typing.errors.map(&:header_line)}"
      end
    end
  end

  def test_raw_new_then_use_thing_still_flags_precondition
    # Soundness: constructing the record directly (no `build`) does NOT
    # get the return-value refinement — the precondition must still fire.
    with_checker(RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::REProxy
        def run_bad
          record = RERecord.new
          record.use_thing
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_thing_contract, postconditions: build_postcondition) do |construction, typing|
        construction.synthesize(source.node)

        precondition_errors = typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied)
        assert_equal 1, precondition_errors.size,
                     "a raw `RERecord.new` must not receive the build establishment, got: #{typing.errors.map(&:header_line)}"
        assert_equal :use_thing, precondition_errors.first.method_name
      end
    end
  end

  def test_no_postcondition_means_precondition_still_flagged
    # Without the `build` postcondition, `record = build` imports nothing
    # and the precondition fires — confirms the establishment is what
    # discharges it, not some unrelated flow.
    with_checker(RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::REProxy
        def run_ok
          record = build
          record.use_thing
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_thing_contract, postconditions: Postconditions::Store.empty) do |construction, typing|
        construction.synthesize(source.node)

        precondition_errors = typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied)
        assert_equal 1, precondition_errors.size,
                     "without the build postcondition the precondition must be flagged"
      end
    end
  end
end
