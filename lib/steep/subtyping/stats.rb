module Steep
  module Subtyping
    class Stats
      class KindStats
        attr_accessor :calls, :hits, :computes, :toplevel_computes, :toplevel_compute_time

        def initialize
          @calls = 0
          @hits = 0
          @computes = 0
          @toplevel_computes = 0
          @toplevel_compute_time = 0.0
        end
      end

      class RelationStats
        attr_accessor :calls, :hits, :toplevel_compute_time

        def initialize
          @calls = 0
          @hits = 0
          @toplevel_compute_time = 0.0
        end
      end

      attr_reader :kinds, :relations, :caches
      attr_reader :calls, :reflexive_calls, :hits, :toplevel_hits, :reflexive_hits,
                  :computes, :toplevel_computes, :computes_with_unusable_cache,
                  :assumption_successes, :context_misses, :shortcuts
      attr_reader :toplevel_compute_time
      attr_reader :shapes, :shape_calls
      attr_reader :shape_time

      def initialize
        @kinds = {}
        @relations = {}
        @caches = []
        @ground_relations = Set[]

        @calls = 0
        @reflexive_calls = 0
        @hits = 0
        @toplevel_hits = 0
        @reflexive_hits = 0
        @computes = 0
        @toplevel_computes = 0
        @computes_with_unusable_cache = 0
        @assumption_successes = 0
        @context_misses = 0
        @shortcuts = 0
        @toplevel_compute_time = 0.0

        @shapes = {}
        @shape_calls = 0
        @shape_time = 0.0
        @shape_depth = 0
      end

      def self.active
        return @active if defined?(@active)

        @active =
          if ENV["STEEP_SUBTYPING_STATS"] || ENV["STEEP_SUBTYPING_STATS_FILE"]
            stats = new()
            at_exit { stats.report() }
            stats
          end
      end

      def self.active=(stats)
        @active = stats
      end

      def register_cache(cache)
        caches << cache
      end

      def hit(relation, toplevel:)
        count_call(relation, hit: true)
        @hits += 1
        @toplevel_hits += 1 if toplevel
      end

      def assumption(relation)
        count_call(relation, hit: false)
        @assumption_successes += 1
      end

      def shortcut(relation)
        count_call(relation, hit: false)
        @shortcuts += 1
      end

      def measure_shape(type)
        @shape_depth += 1
        if @shape_depth == 1
          @shape_calls += 1
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            yield
          ensure
            @shape_depth -= 1
            time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            @shape_time += time
            counts = (shapes[type] ||= [0, 0.0])
            counts[0] += 1
            counts[1] += time
          end
        else
          begin
            yield
          ensure
            @shape_depth -= 1
          end
        end
      end

      def compute(relation, cached:, toplevel:, ground:)
        count_call(relation, hit: false)
        @computes += 1
        @toplevel_computes += 1 if toplevel
        @computes_with_unusable_cache += 1 if cached

        if ground
          if @ground_relations.include?(relation)
            @context_misses += 1
          else
            @ground_relations << relation
          end
        end

        kind = kind_stats(relation)
        kind.computes += 1
        kind.toplevel_computes += 1 if toplevel
      end

      def compute_time(relation, time)
        @toplevel_compute_time += time
        kind_stats(relation).toplevel_compute_time += time
        (relations[relation] ||= RelationStats.new).toplevel_compute_time += time
      end

      def count_call(relation, hit:)
        @calls += 1
        reflexive = relation.sub_type == relation.super_type
        @reflexive_calls += 1 if reflexive
        @reflexive_hits += 1 if reflexive && hit

        kind = kind_stats(relation)
        kind.calls += 1
        kind.hits += 1 if hit

        rel = (relations[relation] ||= RelationStats.new)
        rel.calls += 1
        rel.hits += 1 if hit
      end

      def kind_stats(relation)
        kinds[relation_kind(relation)] ||= KindStats.new
      end

      def type_kind(type)
        case type
        when AST::Types::Name::Instance then "Instance"
        when AST::Types::Name::Singleton then "Singleton"
        when AST::Types::Name::Interface then "Interface"
        when AST::Types::Name::Alias then "Alias"
        when AST::Types::Union then "Union"
        when AST::Types::Intersection then "Intersection"
        when AST::Types::Tuple then "Tuple"
        when AST::Types::Record then "Record"
        when AST::Types::Proc then "Proc"
        when AST::Types::Literal then "Literal"
        when AST::Types::Boolean then "bool"
        when AST::Types::Var then "Var"
        when AST::Types::Any then "untyped"
        when AST::Types::Top then "top"
        when AST::Types::Bot then "bot"
        when AST::Types::Void then "void"
        when AST::Types::Nil then "nil"
        when AST::Types::Self then "self"
        when AST::Types::Instance then "instance"
        when AST::Types::Class then "class"
        when AST::Types::Logic::Base then "logic"
        else
          type.class.name || "?"
        end
      end

      def relation_kind(relation)
        "#{type_kind(relation.sub_type)} <: #{type_kind(relation.super_type)}"
      end

      def entry_stats
        entries = 0
        ground_entries = 0
        contexts = Set[]
        reflexive = 0
        successes = 0

        caches.each do |cache|
          cache.subtypes.each do |key, value|
            relation, self_type, instance_type, class_type, bounds = key
            entries += 1
            contexts << [self_type, instance_type, class_type, bounds]
            reflexive += 1 if relation.sub_type == relation.super_type
            successes += 1 if value.success?
          end

          cache.ground_subtypes.each do |relation, value|
            entries += 1
            ground_entries += 1
            reflexive += 1 if relation.sub_type == relation.super_type
            successes += 1 if value.success?
          end
        end

        {
          entries: entries,
          ground_entries: ground_entries,
          distinct_contexts: contexts.size,
          reflexive_entries: reflexive,
          success_values: successes,
        }
      end

      def measure_exclusive_memory!
        require "objspace"

        2.times { GC.start }
        before = ObjectSpace.memsize_of_all
        caches.each do |cache|
          cache.subtypes.clear
          cache.ground_subtypes.clear
        end
        2.times { GC.start }
        after = ObjectSpace.memsize_of_all

        before - after
      end

      def percent(count, total)
        return "-" if total.zero?
        "#{(count * 100.0 / total).round(1)}%"
      end

      def report
        return if calls.zero?

        entry_stats = entry_stats()
        exclusive_memory = ENV["STEEP_SUBTYPING_STATS_MEMORY"] ? measure_exclusive_memory! : nil

        if ENV["STEEP_SUBTYPING_STATS"]
          report_text($stderr, entry_stats, exclusive_memory)
        end

        if path = ENV["STEEP_SUBTYPING_STATS_FILE"]
          require "json"
          File.open(path, "a") do |io|
            io.puts(JSON.generate(as_json(entry_stats, exclusive_memory)))
          end
        end
      end

      def report_text(io, entry_stats, exclusive_memory)
        io.puts "[steep #{VERSION}] subtyping cache stats (pid #{Process.pid})"
        io.puts "  check_type calls: #{calls} (reflexive: #{reflexive_calls}, distinct relations: #{relations.size})"
        io.puts "  cache hits: #{hits} (#{percent(hits, calls)}; top-level: #{toplevel_hits}, reflexive: #{reflexive_hits})"
        io.puts "  computed: #{computes} (top-level: #{toplevel_computes}, taking #{toplevel_compute_time.round(2)}s; cached but unusable: #{computes_with_unusable_cache})"
        io.puts "  trivial shortcuts (uncached): #{shortcuts}"
        io.puts "  context-fragmented misses: #{context_misses} (#{percent(context_misses, computes)} of computes are ground relations already computed in another context)"
        io.puts "  assumption successes: #{assumption_successes}"
        io.puts "  cache entries: #{entry_stats[:entries]} (ground: #{entry_stats[:ground_entries]}, contexts: #{entry_stats[:distinct_contexts]}, reflexive: #{entry_stats[:reflexive_entries]}, successes: #{entry_stats[:success_values]})"
        if exclusive_memory
          io.puts "  memory exclusively retained by cache: #{(exclusive_memory / 1024.0 / 1024).round(1)}MB"
        end
        io.puts "  top kinds by calls:"
        kinds.sort_by {|_, stats| -stats.calls }.take(15).each do |kind, stats|
          io.puts "    %-40s %8d calls %6s hit %8d computes %8.2fs top-level compute" % [
            kind, stats.calls, percent(stats.hits, stats.calls), stats.computes, stats.toplevel_compute_time
          ]
        end

        if shape_calls > 0
          io.puts "  shape calls: #{shape_calls} taking #{shape_time.round(2)}s (distinct targets: #{shapes.size}; overlaps with compute time above)"
          by_kind = {} #: Hash[String, [Integer, Float]]
          shapes.each do |type, (calls, time)|
            entry = (by_kind[type_kind(type)] ||= [0, 0.0])
            entry[0] += calls
            entry[1] += time
          end
          io.puts "  shape time by target kind:"
          by_kind.sort_by {|_, (_, time)| -time }.take(8).each do |kind, (calls, time)|
            io.puts "    %-40s %8d calls %8.2fs" % [kind, calls, time]
          end
        end
      end

      def as_json(entry_stats, exclusive_memory)
        {
          steep_version: VERSION,
          pid: Process.pid,
          calls: calls,
          reflexive_calls: reflexive_calls,
          distinct_relations: relations.size,
          hits: hits,
          toplevel_hits: toplevel_hits,
          reflexive_hits: reflexive_hits,
          computes: computes,
          toplevel_computes: toplevel_computes,
          toplevel_compute_time: toplevel_compute_time.round(4),
          computes_with_unusable_cache: computes_with_unusable_cache,
          context_misses: context_misses,
          shortcuts: shortcuts,
          assumption_successes: assumption_successes,
          cache: entry_stats,
          exclusive_memory_bytes: exclusive_memory,
          kinds: kinds.sort_by {|_, stats| -stats.calls }.map do |kind, stats|
            {
              kind: kind,
              calls: stats.calls,
              hits: stats.hits,
              computes: stats.computes,
              toplevel_computes: stats.toplevel_computes,
              toplevel_compute_time: stats.toplevel_compute_time.round(4),
            }
          end,
          top_relations: relations.sort_by {|_, stats| -stats.calls }.take(25).map do |relation, stats|
            {
              relation: relation.to_s,
              calls: stats.calls,
              hits: stats.hits,
            }
          end,
          top_relations_by_compute_time: relations.each.select {|_, stats| stats.toplevel_compute_time > 0 }.sort_by {|_, stats| -stats.toplevel_compute_time }.take(15).map do |relation, stats|
            {
              relation: relation.to_s,
              calls: stats.calls,
              hits: stats.hits,
              toplevel_compute_time: stats.toplevel_compute_time.round(4),
            }
          end,
          shape_calls: shape_calls,
          shape_time: shape_time.round(4),
          top_shapes_by_time: shapes.sort_by {|_, (_, time)| -time }.take(20).map do |type, (calls, time)|
            {
              type: type.to_s,
              calls: calls,
              time: time.round(4),
            }
          end,
        }
      end
    end
  end
end
