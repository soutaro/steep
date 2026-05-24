require_relative "test_helper"

# Unit tests for the `Postconditions::MarkerNaming` convention. Both
# Steep's `Postconditions::Inferrer` and rbs_infer's marker-class
# generator follow this convention verbatim; if they ever drift, the
# postcondition references a class that doesn't exist in RBS and the
# refinement silently no-ops at apply time. These tests pin the rules.
class PostconditionsMarkerNamingTest < Minitest::Test
  MarkerNaming = Steep::Postconditions::MarkerNaming

  def test_marker_name_for_basic_snake_case
    assert_equal "::Venue::AfterSetDefaultName",
                 MarkerNaming.marker_name_for("Venue", :set_default_name)
  end

  def test_marker_name_for_nested_class
    assert_equal "::Concerts::Venue::AfterSetDefaultName",
                 MarkerNaming.marker_name_for("Concerts::Venue", :set_default_name)
  end

  def test_marker_name_for_accepts_string_method_name
    assert_equal "::Venue::AfterClearName",
                 MarkerNaming.marker_name_for("Venue", "clear_name")
  end

  def test_marker_name_strips_predicate_suffix
    assert_equal "::Venue::AfterConfirmed",
                 MarkerNaming.marker_name_for("Venue", :confirmed?)
  end

  def test_marker_name_strips_bang_suffix
    assert_equal "::Venue::AfterUpdate",
                 MarkerNaming.marker_name_for("Venue", :update!)
  end

  def test_marker_name_strips_setter_suffix
    assert_equal "::Venue::AfterName",
                 MarkerNaming.marker_name_for("Venue", :name=)
  end

  def test_marker_name_normalizes_leading_double_colon
    assert_equal "::Venue::AfterSetDefaultName",
                 MarkerNaming.marker_name_for("::Venue", :set_default_name)
  end

  def test_marker_name_handles_single_word_method
    assert_equal "::Venue::AfterMount",
                 MarkerNaming.marker_name_for("Venue", :mount)
  end

  def test_narrowed_self_type_for_composes_intersection
    assert_equal "::Venue & ::Venue::AfterSetDefaultName",
                 MarkerNaming.narrowed_self_type_for("Venue", :set_default_name)
  end

  def test_narrowed_self_type_for_nested_class
    assert_equal "::Concerts::Venue & ::Concerts::Venue::AfterSetDefaultName",
                 MarkerNaming.narrowed_self_type_for("Concerts::Venue", :set_default_name)
  end

  def test_valid_method_name_true_for_normal_methods
    assert MarkerNaming.valid_method_name?(:set_default_name)
    assert MarkerNaming.valid_method_name?(:confirmed?)
    assert MarkerNaming.valid_method_name?(:name=)
  end

  def test_valid_method_name_false_for_operator_only_methods
    refute MarkerNaming.valid_method_name?(:"=")
    refute MarkerNaming.valid_method_name?(:"?")
    refute MarkerNaming.valid_method_name?(:"!")
  end

  def test_pascal_case_preserves_acronyms_one_capital_per_segment
    # "url_for" → "UrlFor", not "URLFor". The convention is segment-by-segment
    # capitalize-first, not English-aware acronym detection.
    assert_equal "UrlFor", MarkerNaming.pascal_case("url_for")
  end
end
