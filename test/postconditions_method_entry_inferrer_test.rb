require_relative "test_helper"

class PostconditionsMethodEntryInferrerTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Postconditions = Steep::Postconditions

  RBS_FIXTURE = <<~RBS
    class MEIController
      @performed: bool
      def authenticate_user: () -> void
      def set_thing: () -> void
      def performed?: () -> bool
      def current_user_present?: () -> bool
      def index: () -> void
      def __rbs_infer__run_index: () -> void
      def gate_flow: () -> void
      def helper: () -> void
    end

    class MFoo
      def self.name: () -> String?
      def self.name=: (String? value) -> void
    end

    class MBar
      def foo_name: () -> String?
    end

    class MRun
      def run: () -> void
    end
  RBS

  def sequences_for(ruby)
    result = nil
    with_checker(RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        result = Postconditions::MethodEntryInferrer.sequences(source, typing)
      end
    end
    result
  end

  def test_extracts_handler_and_action_calls_in_order
    sequences = sequences_for(<<~RUBY)
      class MEIController
        def __rbs_infer__run_index
          authenticate_user
          return if performed?
          set_thing if current_user_present?
          return if performed?
          index
        end
      end
    RUBY

    assert_equal 1, sequences.size
    calls = sequences[0].events.select { |e| e[:kind] == :call }
    # `authenticate_user`, `set_thing` (from `if cond`), `index` — the
    # `return if performed?` halt checks and the `current_user_present?`
    # condition are skipped.
    assert_equal [:authenticate_user, :set_thing, :index], calls.map { |c| c[:method_name] }
    assert_equal "MEIController", calls.first[:class_name]
    assert calls.all? { |c| c[:same_self] }, "self-send handlers are same-self"
  end

  def test_defined_method_keys_includes_self_method_annotation
    # A top-level body checked with `@type self_method: X#m` (an ERB template
    # compiled to a method at runtime) IS the source body of `X#m`, so it must
    # contribute `X#m` to the defined-method keys — otherwise the Runner's
    # defined-key filter drops the entry fact a guarded render records for it.
    with_checker(RBS_FIXTURE) do |checker|
      source = parse_ruby(<<~RUBY)
        Object.new
        # @type self_method: MBar#__rbs_infer__body
      RUBY

      keys = Postconditions::MethodEntryInferrer.defined_method_keys(source)
      assert_includes keys, "MBar#__rbs_infer__body"
    end
  end

  def test_defined_method_keys_omits_self_method_when_absent
    with_checker(RBS_FIXTURE) do |checker|
      source = parse_ruby("Object.new\n")
      keys = Postconditions::MethodEntryInferrer.defined_method_keys(source)
      assert_empty keys.grep(/__rbs_infer__body/)
    end
  end

  def test_halt_check_makes_a_flow_regardless_of_method_name
    # No `__rbs_infer__run_` name — the flow is recognized purely by the `return if performed?`
    # halt structure (felixefelip/steep#78, `RUNNER_PREFIX` removed).
    sequences = sequences_for(<<~RUBY)
      class MEIController
        def gate_flow
          authenticate_user
          return if performed?
          index
        end
      end
    RUBY

    assert_equal 1, sequences.size
    kinds = sequences[0].events.map { |e| e[:kind] }
    assert_includes kinds, :halt, "the `return if performed?` is a halt event"
    calls = sequences[0].events.select { |e| e[:kind] == :call }.map { |c| c[:method_name] }
    assert_equal [:authenticate_user, :index], calls
  end

  def test_call_only_method_is_a_sequence_for_transitive_seeding
    # A method with only calls establishes nothing on its own, but under the Runner's
    # fixpoint it FORWARDS its owner's seeded entry facts to its callees. So it must still
    # be a sequence (owned by `MEIController#helper`), carrying its call events.
    sequences = sequences_for(<<~RUBY)
      class MEIController
        def helper
          authenticate_user
          index
        end
      end
    RUBY

    assert_equal 1, sequences.size
    assert_equal "MEIController#helper", sequences[0].owner
    calls = sequences[0].events.select { |e| e[:kind] == :call }
    assert_equal [:authenticate_user, :index], calls.map { |c| c[:method_name] }
  end

  def test_truly_empty_body_is_not_a_sequence
    sequences = sequences_for(<<~RUBY)
      class MEIController
        def helper
        end
      end
    RUBY

    assert_empty sequences
  end

  def test_plain_flow_const_write_then_cross_object_call
    sequences = sequences_for(<<~RUBY)
      class MRun
        def run
          MFoo.name = "x"
          MBar.new.foo_name
        end
      end
    RUBY

    assert_equal 1, sequences.size
    events = sequences[0].events

    # The const-write comes first, before any call event.
    assert_equal :const_write, events[0][:kind]
    assert_equal "MFoo", events[0][:base]
    assert_equal "name", events[0][:attr]
    assert events[0][:nonnil], "a String literal RHS is non-nil"

    # `MBar.new.foo_name` records `foo_name` (the chain walk reaches it even though `.new` is
    # its receiver), as a cross-object call.
    foo = events.find { |e| e[:kind] == :call && e[:method_name] == :foo_name }
    refute_nil foo
    assert_equal "MBar", foo[:class_name]
    refute foo[:same_self], "an instance-receiver call is cross-object"
  end

  def test_nilable_const_write_is_not_nonnil
    sequences = sequences_for(<<~RUBY)
      class MRun
        def run
          # @type var maybe: ::String?
          maybe = nil
          MFoo.name = maybe
          MBar.new.foo_name
        end
      end
    RUBY

    const_write = sequences[0].events.find { |e| e[:kind] == :const_write }
    refute_nil const_write
    refute const_write[:nonnil], "a nilable RHS establishes nothing (invalidates instead)"
  end
end
