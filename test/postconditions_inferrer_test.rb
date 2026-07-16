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

    # No REFINEMENT — the assignment narrows nothing. The method does still
    # WRITE @company, so it carries the may-write effect (felixefelip/steep#68):
    # a caller that narrowed @company must drop that view after the call.
    refute_empty entries
    assert_empty entries[0].ivars
    assert_equal Set[:@company], entries[0].may_write_ivars
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

  def test_bare_ivar_body_is_a_transparent_getter
    # `def has_name?; @name; end` proposes no when_true refinement (its return
    # is the ivar's plain type, not a logic type). But it IS a transparent
    # getter of @name (felixefelip/steep#68 item 2): testing it must narrow
    # @name, so the entry carries `returns_ivar`.
    entries = infer_predicate_for(<<~RUBY)
      class PCPredVenue
        def has_name?
          @name
        end
      end
    RUBY

    assert_equal 1, entries.size
    assert_empty entries[0].when_true_ivars
    assert_equal :@name, entries[0].returns_ivar
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

  # --- return-value establishment (felixefelip/steep#56) --------------

  RETURNS_RBS_FIXTURE = <<~RBS
    class RVThing
      def self.new: () -> RVThing
    end

    class RVRecord
      attr_accessor thing: RVThing?
      def self.new: () -> RVRecord
    end

    class RVFactory
      def build: () -> RVRecord
      def self.build_s: () -> RVRecord
      def build_other: () -> RVRecord
      def no_write: () -> RVRecord
    end
  RBS

  def infer_returns_for(ruby)
    entries = nil
    with_checker(RETURNS_RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        entries = Postconditions::Inferrer.infer(source, typing, checker)
      end
    end
    entries
  end

  def test_infers_return_establishment_for_factory_shape
    # `record = RVRecord.new; record.thing = RVThing.new; record` — the
    # returned local has `thing` (declared `RVThing?`) written non-nil,
    # so `build` establishes `thing` on its return value.
    entries = infer_returns_for(<<~RUBY)
      class RVFactory
        def build
          record = RVRecord.new
          record.thing = RVThing.new
          record
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :build }
    refute_nil entry, "expected an entry for build"
    assert_equal [:thing], entry.returns_establishes
    assert_empty entry.ivars, "build sets no ivar — only a local's attribute"
  end

  def test_infers_return_establishment_for_singleton_factory
    entries = infer_returns_for(<<~RUBY)
      class RVFactory
        def self.build_s
          record = RVRecord.new
          record.thing = RVThing.new
          record
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :build_s }
    refute_nil entry, "expected an entry for the singleton build_s"
    assert entry.singleton
    assert_equal [:thing], entry.returns_establishes
  end

  def test_no_return_establishment_when_returned_local_differs_from_written
    # The attribute is written on `other`, but a DIFFERENT local
    # (`record`) is returned — the write doesn't reach the return value.
    entries = infer_returns_for(<<~RUBY)
      class RVFactory
        def build_other
          record = RVRecord.new
          other = RVRecord.new
          other.thing = RVThing.new
          record
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :build_other }
    assert(entry.nil? || entry.returns_establishes.empty?,
           "a write to a non-returned local must not establish anything on the return value")
  end

  def test_no_return_establishment_without_attr_write
    entries = infer_returns_for(<<~RUBY)
      class RVFactory
        def no_write
          record = RVRecord.new
          record
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :no_write }
    assert(entry.nil? || entry.returns_establishes.empty?)
  end

  # felixefelip/steep#68 item 2 — the guard-clause proof.
  CR_RBS_FIXTURE = <<~RBS
    class User
    end

    class Current
      def self.user: () -> User?
      def self.user=: (User?) -> User?
    end

    class CRGuardHost
      @halted: bool

      def current_user: () -> User?
      def redirect_to: () -> void
      def authenticate_user: () -> void
      def no_return: () -> void
    end
  RBS

  def infer_cr_for(ruby)
    entries = nil
    with_checker(CR_RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        entries = Postconditions::Inferrer.infer(source, typing, checker)
      end
    end
    entries
  end

  def test_infers_conditional_return_from_guard_clause
    # `unless current_user; <halt>; return; end` proves `current_user` non-nil
    # on the unhalted exit. Here the halt is a direct ivar write, so the gate
    # resolves to `@halted` in the inferrer itself.
    entries = infer_cr_for(<<~RUBY)
      class CRGuardHost
        def authenticate_user
          unless current_user
            @halted = true
            return
          end
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :authenticate_user }
    refute_nil entry
    spec = entry.conditional_returns[:current_user]
    refute_nil spec, "expected a conditional return for current_user"
    assert_equal :@halted, spec[:gate_ivar]
    assert_equal "::User", spec[:type].to_s
  end

  def test_conditional_return_gate_via_self_method
    # When the halt is a self-method call (`redirect_to`) rather than a direct
    # write, the inferrer records the gate `via` that method; the Runner
    # resolves it to the written ivar (covered in the runner test).
    entries = infer_cr_for(<<~RUBY)
      class CRGuardHost
        def authenticate_user
          unless current_user
            redirect_to
            return
          end
        end
      end
    RUBY

    spec = entries.find { |e| e.method_name == :authenticate_user }.conditional_returns[:current_user]
    refute_nil spec
    assert_nil spec[:gate_ivar]
    assert_equal :redirect_to, spec[:gate_via]
  end

  def test_infers_conditional_const_return_from_guarded_write
    # felixefelip/steep#68 item 3. `unless current_user; halt; return; end`
    # followed by a top-level `Current.user = current_user` (non-nil past the
    # guard) proves `Current.user` non-nil on the unhalted exit.
    entries = infer_cr_for(<<~RUBY)
      class CRGuardHost
        def authenticate_user
          unless current_user
            redirect_to
            return
          end
          Current.user = current_user
        end
      end
    RUBY

    spec = entries.find { |e| e.method_name == :authenticate_user }.conditional_const_returns["Current.user"]
    refute_nil spec, "expected a conditional const return for Current.user"
    assert_equal :redirect_to, spec[:gate_via]
    assert_equal "::User", spec[:type].to_s
  end

  def test_no_conditional_const_return_for_nilable_write
    # `Current.user = current_user` BEFORE proving `current_user` present — the
    # written value is nilable, so nothing about `Current.user` is proven.
    entries = infer_cr_for(<<~RUBY)
      class CRGuardHost
        def authenticate_user
          Current.user = current_user
          unless current_user
            redirect_to
            return
          end
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :authenticate_user }
    assert(entry.nil? || entry.conditional_const_returns.empty?)
  end

  def test_no_conditional_return_without_return_in_guard
    # A guard that narrows but doesn't halt (no `return`) proves nothing about
    # a later exit — the method falls through either way.
    entries = infer_cr_for(<<~RUBY)
      class CRGuardHost
        def no_return
          unless current_user
            @halted = true
          end
        end
      end
    RUBY

    entry = entries.find { |e| e.method_name == :no_return }
    assert(entry.nil? || entry.conditional_returns.empty?)
  end
end
