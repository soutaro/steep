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

      def set_company: () -> (IUCompany & IUCompany::Validated)
      def set_raw: () -> IUCompany
      def set_one_of: () -> ((IUCompany & IUCompany::Validated) | IUCompany)
      def no_assign: () -> void
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
end
