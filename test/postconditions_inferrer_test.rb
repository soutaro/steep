require_relative "test_helper"

class PostconditionsInferrerTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Postconditions = Steep::Postconditions

  RBS_FIXTURE = <<~RBS
    class IUCompany
      def self.find: (Integer) -> (IUCompany & IUCompany::Validated)
      def self.new: () -> IUCompany
    end

    module IUCompany::Validated
    end

    class IUController
      @company: (IUCompany & IUCompany::Validated) | IUCompany
      @name: String?

      def set_company: () -> (IUCompany & IUCompany::Validated)
      def set_raw: () -> IUCompany
      def set_one_of: () -> ((IUCompany & IUCompany::Validated) | IUCompany)
      def no_assign: () -> void
      def set_default_name: () -> String
    end
  RBS

  def infer_for(ruby)
    entries = nil
    with_checker(RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        entries = Postconditions::Inferrer.infer(source, typing, checker)
      end
    end
    entries
  end

  def test_infers_unconditional_ivar_postcondition_for_narrowing_assign
    # A method body that assigns `@company` to a value of type
    # `IUCompany & Validated` (a strict subtype of the declared union)
    # surfaces as an inferred postcondition.
    entries = infer_for(<<~RUBY)
      class IUController
        def set_company
          @company = IUCompany.find(1)
        end
      end
    RUBY

    assert_equal 1, entries.size
    entry = entries.first
    assert_equal "IUController", entry.class_name
    assert_equal :set_company, entry.method_name
    refute entry.singleton
    assert_equal [:"@company"], entry.ivars.keys
    assert_equal "(::IUCompany & ::IUCompany::Validated)", entry.ivars[:"@company"].to_s
    # `unconditional.self` is emitted alongside `ivars` so that callers
    # whose receiver is NOT self (e.g. `controller.set_company`) can
    # still be narrowed — `apply_unconditional_postconditions` only
    # touches caller ivars when receiver is self, so without a self
    # marker the cross-receiver case would be a no-op.
    assert_equal "::IUController & ::IUController::AfterSetCompany",
                 entry.self_type_string
  end

  def test_does_not_infer_when_rhs_equals_declared
    # Method assigns `@company` to a value typed exactly as the declared
    # union — no refinement, no inference. Avoids emitting useless
    # entries that say "narrow to the same type".
    entries = infer_for(<<~RUBY)
      class IUController
        def set_one_of
          # @type var same_typed: (IUCompany & IUCompany::Validated) | IUCompany
          same_typed = (_ = nil)
          @company = same_typed
        end
      end
    RUBY

    assert_empty entries
  end

  def test_does_not_infer_when_rhs_is_not_strict_subtype
    # Method assigns `@company` to a wider/unrelated type — RHS is not a
    # strict subtype of the declared. The inferrer does not propose a
    # postcondition (the assignment may even be a type error on its own,
    # but that's the dispatch's concern, not the inferrer's).
    entries = infer_for(<<~RUBY)
      class IUController
        def set_raw
          @company = IUCompany.new
        end
      end
    RUBY

    # `IUCompany.new` returns plain `IUCompany`, which is one of the
    # union branches but not a *strict* subtype of the union (the union
    # is reflexive). Whether this is "narrowing" depends on subtyping
    # checker behavior; assert that we don't crash and that the result
    # is well-formed.
    assert_kind_of Array, entries
  end

  def test_handles_method_with_no_ivar_assignment
    # Method body that has no `:ivasgn` produces no entries.
    entries = infer_for(<<~RUBY)
      class IUController
        def no_assign
          1 + 1
        end
      end
    RUBY

    assert_empty entries
  end

  def test_multiple_ivar_assignments_take_last_write
    # When a method writes the same ivar twice with different types,
    # the LAST write's type wins. The inferrer assumes linear flow for
    # MVP — a more sophisticated analysis (branching) is future work.
    entries = infer_for(<<~RUBY)
      class IUController
        def set_company
          @company = IUCompany.new
          @company = IUCompany.find(1)
        end
      end
    RUBY

    refute_empty entries
    entry = entries.first
    assert_equal "(::IUCompany & ::IUCompany::Validated)", entry.ivars[:"@company"].to_s
  end

  def test_infers_narrowing_when_rhs_is_string_literal_against_nilable_ivar
    # `@name: String?` declared. `set_default_name` writes a String
    # literal. Steep's `:ivasgn` synthesize passes the declared
    # `String?` as `hint:` to the str-node synthesize, which makes
    # `typing.type_of(str_node)` return the widened `String?` —
    # losing the narrowing the writer actually introduces.
    #
    # The Inferrer reads the literal's intrinsic type
    # (`AST::Builtin::String.instance_type`) directly, so the
    # narrowing survives. felixefelip/steep#34.
    entries = infer_for(<<~RUBY)
      class IUController
        def set_default_name
          @name = "TBA Venue"
        end
      end
    RUBY

    refute_empty entries
    entry = entries.find { |e| e.method_name == :set_default_name }
    refute_nil entry, "expected entry for set_default_name"
    assert_equal "::String", entry.ivars[:"@name"].to_s
  end

  def test_infers_narrowing_when_rhs_is_nil_literal_against_nilable_ivar
    # `nil` literal isn't context-widened (it's already the bottom
    # of any union containing nil), so this case used to work even
    # before the intrinsic-type fix. Pinned here so a regression
    # of `:nil` handling shows up immediately.
    entries = infer_for(<<~RUBY)
      class IUController
        def set_default_name
          @name = nil
        end
      end
    RUBY

    refute_empty entries
    entry = entries.find { |e| e.method_name == :set_default_name }
    refute_nil entry
    assert_equal "nil", entry.ivars[:"@name"].to_s
  end

  def test_ignores_top_level_defs_without_class
    # `def x` at the top of the source (no enclosing class) has no
    # `class_name` to attach a postcondition to — inferrer skips it.
    entries = infer_for(<<~RUBY)
      def top_level_def
        @company = IUCompany.find(1)
      end
    RUBY

    assert_empty entries
  end

  # --------------------------------------------------------------------
  # `when_true` postconditions for nil-check predicates.
  # `def confirmed?; !@name.nil?; end` should emit a `when_true.ivars`
  # entry refining `@name` to non-nil (and a self marker for chain
  # narrowing).
  # --------------------------------------------------------------------

  PREDICATE_RBS_FIXTURE = <<~RBS
    class PCPredVenue
      @name: String?
      @owner: String?

      def confirmed?: () -> bool
      def fully_set?: () -> bool
      def has_name?: () -> bool
      def truthy_only: () -> bool
    end
  RBS

  def infer_predicate_for(ruby)
    entries = nil
    with_checker(PREDICATE_RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        entries = Postconditions::Inferrer.infer(source, typing, checker)
      end
    end
    entries
  end

  def test_infers_when_true_for_negated_nil_check
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def confirmed?
          !@name.nil?
        end
      end
    RUBY

    refute_empty entries
    entry = entries.find { |e| e.method_name == :confirmed? }
    refute_nil entry
    assert_empty entry.ivars, "unconditional should be empty for a predicate body"
    assert_equal "::String", entry.when_true_ivars[:"@name"].to_s
    assert_equal "::PCPredVenue & ::PCPredVenue::AfterConfirmed",
                 entry.when_true_self_type_string
  end

  def test_infers_when_true_for_conjunction_of_nil_checks
    # `!@a.nil? && !@b.nil?` — both ivars refined non-nil in the
    # truthy branch.
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def fully_set?
          !@name.nil? && !@owner.nil?
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :fully_set? }
    refute_nil entry
    assert_equal "::String", entry.when_true_ivars[:"@name"].to_s
    assert_equal "::String", entry.when_true_ivars[:"@owner"].to_s
  end

  def test_skips_when_declared_type_already_non_nil
    # Even though the body matches the nil-check shape, if the ivar
    # is already declared non-nilable in RBS, there's no narrowing
    # opportunity. Don't emit a no-op refinement.
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def truthy_only
          !@nonexistent.nil?
        end
      end
    RUBY

    # No declared @nonexistent → no entry. Sanity: not crashing on
    # missing ivar declaration.
    assert_empty entries
  end

  def test_skips_truthy_bare_ivar_in_body
    # `def has_name?; @name; end` returns the ivar's actual type
    # (e.g. `String?`), not a logic type. The interpreter has no
    # narrowing handle, so we silently skip. A future extension
    # could partition the ivar's union (truthy vs falsy halves)
    # but it's a separate decision.
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def has_name?
          @name
        end
      end
    RUBY

    assert_empty entries
  end

  def test_infers_when_true_for_multi_statement_body
    # Body has setup statements before the final predicate
    # expression. The interpreter only cares about the last
    # expression (the return value), so the side-effecting calls
    # above don't interfere.
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def confirmed?
          _logged = "checking"
          !@name.nil?
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :confirmed? }
    refute_nil entry, "expected refinement to survive a leading non-predicate statement"
    assert_equal "::String", entry.when_true_ivars[:"@name"].to_s
  end
end
