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
      def helper: () -> void
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
    names = sequences[0].calls.map { |c| c[:method_name] }
    # `authenticate_user`, `set_thing` (from `if cond`), `index` — the
    # `return if performed?` halt checks and the `current_user_present?`
    # condition are skipped.
    assert_equal [:authenticate_user, :set_thing, :index], names
    assert_equal "MEIController", sequences[0].calls.first[:class_name]
  end

  def test_ignores_non_runner_methods
    sequences = sequences_for(<<~RUBY)
      class MEIController
        def helper
          authenticate_user
          index
        end
      end
    RUBY

    assert_empty sequences
  end
end
