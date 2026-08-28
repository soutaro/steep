require_relative "test_helper"

class SubtypingStatsTest < Minitest::Test
  include TestHelper
  include Steep

  include FactoryHelper

  Relation = Subtyping::Relation
  Constraints = Subtyping::Constraints
  Stats = Subtyping::Stats

  def with_checker(&block)
    with_factory({ "a.rbs" => <<-EOS }, nostdlib: false) do |factory|
class Foo
end
    EOS
      builder = Interface::Builder.new(factory, implicitly_returns_nil: true)
      yield Subtyping::Check.new(builder: builder)
    end
  end

  def parse_type(string, checker:)
    checker.factory.type(RBS::Parser.parse_type(string))
  end

  def test_stats_counts_hits_and_computes
    Stats.active = Stats.new()

    with_checker do |checker|
      # Cache#initialize registers itself to the active Stats
      stats = Stats.active or raise

      relation = Relation.new(
        sub_type: parse_type("::Foo", checker: checker),
        super_type: parse_type("::Object", checker: checker)
      )

      2.times do
        checker.check(
          relation,
          self_type: parse_type("self", checker: checker),
          instance_type: AST::Types::Instance.new,
          class_type: AST::Types::Class.new,
          constraints: Constraints.empty
        )
      end

      assert_operator stats.calls, :>, 0
      assert_operator stats.computes, :>, 0
      # The second check must hit the cache
      assert_operator stats.hits, :>, 0
      assert_operator stats.toplevel_hits, :>, 0
      assert_operator stats.toplevel_compute_time, :>, 0.0

      assert_operator stats.kinds, :key?, "Instance <: Instance"
      kind = stats.kinds.fetch("Instance <: Instance")
      assert_operator kind.calls, :>, 0
      assert_operator kind.hits, :>, 0

      assert_equal stats.calls, stats.hits + stats.computes + stats.assumption_successes + stats.shortcuts

      entry_stats = stats.entry_stats
      assert_operator entry_stats[:entries], :>, 0
      assert_operator entry_stats[:ground_entries], :>, 0

      json = stats.as_json(entry_stats, nil)
      assert_equal stats.calls, json[:calls]
      refute_empty json[:kinds]
      refute_empty json[:top_relations]
      refute_empty json[:top_relations_by_compute_time]

      io = StringIO.new
      stats.report_text(io, entry_stats, nil)
      assert_includes io.string, "subtyping cache stats"
      assert_includes io.string, "Instance <: Instance"
    end
  ensure
    Stats.active = nil
  end

  def test_ground_relations_cached_across_contexts
    Stats.active = Stats.new()

    with_checker do |checker|
      stats = Stats.active or raise

      relation = Relation.new(
        sub_type: parse_type("::Foo", checker: checker),
        super_type: parse_type("::Object", checker: checker)
      )

      # The same ground relation in two different contexts: the context is not part
      # of the cache key for ground relations, so the second check hits.
      [parse_type("::Foo", checker: checker), parse_type("::Object", checker: checker)].each do |self_type|
        checker.check(
          relation,
          self_type: self_type,
          instance_type: AST::Types::Instance.new,
          class_type: AST::Types::Class.new,
          constraints: Constraints.empty
        )
      end

      assert_operator stats.hits, :>, 0
      assert_equal 0, stats.context_misses
      assert_operator checker.cache.ground_subtypes, :key?, relation
    end
  ensure
    Stats.active = nil
  end

  def test_trivial_relations_not_cached
    Stats.active = Stats.new()

    with_checker do |checker|
      stats = Stats.active or raise

      foo = parse_type("::Foo", checker: checker)

      [
        Relation.new(sub_type: foo, super_type: foo),
        Relation.new(sub_type: foo, super_type: parse_type("untyped", checker: checker)),
        Relation.new(sub_type: foo, super_type: parse_type("void", checker: checker)),
        Relation.new(sub_type: foo, super_type: parse_type("top", checker: checker)),
        Relation.new(sub_type: parse_type("bot", checker: checker), super_type: foo),
      ].each do |relation|
        result = checker.check(
          relation,
          self_type: parse_type("self", checker: checker),
          instance_type: AST::Types::Instance.new,
          class_type: AST::Types::Class.new,
          constraints: Constraints.empty
        )
        assert_predicate result, :success?
      end

      assert_equal 5, stats.shortcuts
      assert_equal 0, stats.computes
      assert_predicate checker.cache, :no_subtype_cache?
    end
  ensure
    Stats.active = nil
  end

  def test_cached_success_has_no_derivation_tree
    with_checker do |checker|
      relation = Relation.new(
        sub_type: parse_type("::Foo", checker: checker),
        super_type: parse_type("::Object", checker: checker)
      )

      result = checker.check(
        relation,
        self_type: parse_type("self", checker: checker),
        instance_type: AST::Types::Instance.new,
        class_type: AST::Types::Class.new,
        constraints: Constraints.empty
      )

      assert_predicate result, :success?
      assert_instance_of Subtyping::Result::Success, checker.cache.ground(relation)
    end
  end

  def test_stats_inactive_by_default
    Stats.active = nil

    with_checker do |checker|
      relation = Relation.new(
        sub_type: parse_type("::Foo", checker: checker),
        super_type: parse_type("::Object", checker: checker)
      )

      result = checker.check(
        relation,
        self_type: parse_type("self", checker: checker),
        instance_type: AST::Types::Instance.new,
        class_type: AST::Types::Class.new,
        constraints: Constraints.empty
      )

      assert_predicate result, :success?
    end
  end
end
