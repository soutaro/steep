#!/usr/bin/env ruby
# Benchmark harness for Steep's subtyping cache (Steep::Subtyping::Cache).
#
# Runs the same type checking pipeline as `steep check` (signature validation +
# source type checking) in a single process, so that one Subtyping::Check /
# Cache instance is shared per target, and measures wall-clock time per phase.
#
# Usage:
#   bundle exec ruby bin/subtyping_cache_bench.rb
#
# Env vars:
#   CACHE_MODE=on|off|none
#                       "off" disables the cache (lookups always miss, stores are
#                       dropped, but check_type still pays the cache bookkeeping);
#                       "none" removes the caching logic from check_type entirely
#   CACHE_STATS=1       collect Steep::Subtyping::Stats and include it in the JSON
#                       (adds overhead; do not trust timing from a stats run)
#   KIND=1              (with CACHE_STATS=1) include per-relation-kind statistics
#                       and the most frequent relations
#   TIME_SHARE=1        measure wall-clock time spent inside top-level check_type
#                       calls, to see the share of subtyping in type checking
#   MEM=1               analyze cache memory: entry composition, reachable size,
#                       and memory freed by clearing the cache
#   CLEAR_PER_FILE=1    clear the context-keyed cache table after each file, to
#                       evaluate bounding memory by per-file eviction
#   TARGETS=app,test    Steepfile targets to check (default: app)
#   FILES=n             limit the number of source files (for quick runs)
#   DIAG_DUMP=path      write all diagnostics to a file, for comparing modes

Encoding.default_external = Encoding::UTF_8

require "steep"
require "benchmark"
require "json"

MODE = ENV.fetch("CACHE_MODE", "on")
STATS = ENV["CACHE_STATS"] == "1"
TARGET_NAMES = (ENV["TARGETS"] || "app").split(",").map(&:to_sym)
FILE_LIMIT = ENV["FILES"]&.to_i

case MODE
when "off"
  # Cache lookups always miss and stores are dropped, but check_type still pays
  # the bookkeeping cost (cache_bounds, free_variables, lookup call).
  module CacheOff
    def [](relation, self_type, instance_type, class_type, bounds)
      nil
    end

    def []=(relation, self_type, instance_type, class_type, bounds, value)
      value
    end

    def ground(relation)
      nil
    end

    def store_ground(relation, value)
      value
    end
  end
  Steep::Subtyping::Cache.prepend(CacheOff)
when "none"
  # Remove the caching logic entirely: no cache_bounds, no free_variables, no
  # lookup, no store. Shows what check_type would cost with no cache code at all.
  module NoCacheCheckType
    def check_type(relation)
      if assumptions.size > Steep::Subtyping::Check::ABORT_LIMIT
        return Failure(relation, Steep::Subtyping::Result::Failure::LoopAbort.new)
      end

      relation.type!

      Steep.logger.tagged(-> { "#{relation.sub_type} <: #{relation.super_type}" }) do
        if assumptions.member?(relation)
          success(relation)
        else
          push_assumption(relation) do
            check_type0(relation)
          end
        end
      end
    end
  end
  Steep::Subtyping::Check.prepend(NoCacheCheckType)
end

if ENV["TIME_SHARE"] == "1"
  # Accumulates wall-clock time spent inside top-level check_type calls, to
  # estimate the share of type checking spent on subtyping at all.
  module SubtypingTimeShare
    STATE = { depth: 0, time: 0.0, calls: 0 }

    def check_type(relation)
      state = STATE
      if state[:depth].zero?
        state[:calls] += 1
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          state[:depth] += 1
          super
        ensure
          state[:depth] -= 1
          state[:time] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end
      else
        super
      end
    end
  end
  Steep::Subtyping::Check.prepend(SubtypingTimeShare)
end

FILE_IDX = [0]

def type_kind(type)
  case type
  when Steep::AST::Types::Name::Instance then "Instance"
  when Steep::AST::Types::Name::Singleton then "Singleton"
  when Steep::AST::Types::Name::Interface then "Interface"
  when Steep::AST::Types::Name::Alias then "Alias"
  when Steep::AST::Types::Union then "Union"
  when Steep::AST::Types::Intersection then "Intersection"
  when Steep::AST::Types::Tuple then "Tuple"
  when Steep::AST::Types::Record then "Record"
  when Steep::AST::Types::Proc then "Proc"
  when Steep::AST::Types::Literal then "Literal"
  when Steep::AST::Types::Boolean then "bool"
  when Steep::AST::Types::Var then "Var"
  when Steep::AST::Types::Any then "untyped"
  when Steep::AST::Types::Top then "top"
  when Steep::AST::Types::Bot then "bot"
  when Steep::AST::Types::Void then "void"
  when Steep::AST::Types::Nil then "nil"
  when Steep::AST::Types::Self then "self"
  when Steep::AST::Types::Instance then "instance"
  when Steep::AST::Types::Class then "class"
  when Steep::AST::Types::Logic::Base then "logic"
  else type.class.name || "?"
  end
end

def relation_kind(relation)
  "#{type_kind(relation.sub_type)} <: #{type_kind(relation.super_type)}"
end

if STATS
  # Use the collector built into Steep (see Steep::Subtyping::Stats)
  Steep::Subtyping::Stats.active = Steep::Subtyping::Stats.new()
end

steepfile = Pathname.pwd + "Steepfile"
project = Steep::Project.new(steepfile_path: steepfile)
Steep::Project::DSL.parse(project, steepfile.read, filename: steepfile.to_s)

loader = Steep::Services::FileLoader.new(base_dir: project.base_dir)

service = nil
boot_time = Benchmark.realtime do
  service = Steep::Services::TypeCheckService.new(project: project)
end

targets = project.targets.select {|t| TARGET_NAMES.include?(t.name) }
raise "no matching targets: #{TARGET_NAMES}" if targets.empty?

# Load files of all targets: signature files of non-unreferenced targets are
# shared with the other targets' environments (see TypeCheckService#update_signature).
changes = {}
project.targets.each do |target|
  loader.each_path_in_target(target) do |path|
    changes[path] ||= [Steep::Services::ContentChange.string((project.base_dir + path).read)]
  end
end

update_time = Benchmark.realtime { service.update(changes: changes) }

result = {
  mode: MODE,
  stats: STATS,
  targets: TARGET_NAMES,
  boot: boot_time.round(2),
  update: update_time.round(2),
  phases: {},
}

targets.each do |target|
  sig_paths = loader.each_path_in_patterns(target.signature_pattern).to_a
  src_paths = loader.each_path_in_patterns(target.source_pattern).to_a
  src_paths = src_paths.first(FILE_LIMIT) if FILE_LIMIT

  # Clears only the context-keyed table: ground entries stay valid across files,
  # while context-keyed entries are bound to the file's classes.
  clear_per_file = ENV["CLEAR_PER_FILE"] == "1"
  clear_cache = -> do
    check = service.signature_services.fetch(target.name).current_subtyping
    check.cache.subtypes.clear if check
  end

  sig_time = Benchmark.realtime do
    sig_paths.each do |path|
      FILE_IDX[0] += 1
      service.validate_signature(path: path, target: target)
      clear_cache.() if clear_per_file
    end
  end

  src_time = Benchmark.realtime do
    src_paths.each do |path|
      FILE_IDX[0] += 1
      service.typecheck_source(path: path, target: target)
      clear_cache.() if clear_per_file
    end
  end

  check = service.signature_services.fetch(target.name).current_subtyping
  result[:phases][target.name] = {
    sig_files: sig_paths.size,
    sig_time: sig_time.round(2),
    src_files: src_paths.size,
    src_time: src_time.round(2),
    cache_entries: check && (check.cache.subtypes.size + check.cache.ground_subtypes.size),
  }
end

diagnostics_count = service.diagnostics.sum {|_, diags| diags.size }
result[:diagnostics] = diagnostics_count

if ENV["MEM"] == "1"
  require "objspace"

  rss_kb = -> { File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i }

  checks = targets.filter_map {|t| service.signature_services.fetch(t.name).current_subtyping }

  # Flatten entries as [context, relation, value] triples; ground entries have no context
  entries = []
  checks.each do |check|
    check.cache.subtypes.each do |key, val|
      rel, self_type, instance_type, class_type, bounds = key
      entries << [[self_type, instance_type, class_type, bounds], rel, val]
    end
    check.cache.ground_subtypes.each do |rel, val|
      entries << [nil, rel, val]
    end
  end

  # Composition of cache entries
  contexts = Hash.new(0)
  value_classes = Hash.new(0)
  empty_bounds = 0
  success_values = 0
  reflexive_entries = 0
  ground_entries = 0
  entries.each do |context, rel, value|
    if context
      contexts[context] += 1
      empty_bounds += 1 if context[3].empty?
    else
      ground_entries += 1
    end
    value_classes[value.class.name.sub("Steep::Subtyping::Result::", "")] += 1
    success_values += 1 if value.success?
    reflexive_entries += 1 if rel.sub_type == rel.super_type
  end

  # Count result-tree nodes retained by cached values, split by success/failure.
  # Cached sub-results are shared between parents, so count unique objects
  # (memory-relevant) and total visits (tree size as seen by each entry).
  seen_results = {}
  count_tree = ->(result) do
    unique = 0
    visits = 0
    stack = [result]
    while r = stack.pop
      visits += 1
      unless seen_results[r.object_id]
        seen_results[r.object_id] = true
        unique += 1
      end
      case r
      when Steep::Subtyping::Result::Expand
        stack << r.child
      when Steep::Subtyping::Result::All, Steep::Subtyping::Result::Any
        stack.concat(r.branches)
      end
    end
    [unique, visits]
  end
  success_nodes = 0
  failure_nodes = 0
  success_visits = 0
  failure_visits = 0
  entries.each do |_, _, value|
    unique, visits = count_tree[value]
    if value.success?
      success_nodes += unique
      success_visits += visits
    else
      failure_nodes += unique
      failure_visits += visits
    end
  end

  # Memory reachable from the cache (over-counts objects shared with the env)
  reachable_bytes = 0
  reachable_count = 0
  seen = {}
  stack = checks.map {|c| c.cache.subtypes } + checks.map {|c| c.cache.ground_subtypes }
  while obj = stack.pop
    next if seen[obj.object_id]
    seen[obj.object_id] = true
    reachable_bytes += ObjectSpace.memsize_of(obj)
    reachable_count += 1
    ObjectSpace.reachable_objects_from(obj)&.each do |o|
      case o
      when Module, Symbol, Integer, Float, ObjectSpace::InternalObjectWrapper, nil, true, false
        # skip
      else
        stack << o unless seen[o.object_id]
      end
    end
  end

  entries_by_kind = Hash.new {|h, k| h[k] = [0, 0] }
  entries.each do |_, rel, value|
    pair = entries_by_kind[relation_kind(rel)]
    pair[0] += 1
    pair[1] += 1 if value.success?
  end

  mem_summary = {
    entries_total: contexts.values.sum + ground_entries,
    ground_entries: ground_entries,
    distinct_contexts: contexts.size,
    top_context_entries: contexts.values.max,
    empty_bounds_entries: empty_bounds,
    reflexive_entries: reflexive_entries,
    success_values: success_values,
    value_classes: value_classes,
    success_tree_nodes_unique: success_nodes,
    success_tree_visits: success_visits,
    failure_tree_nodes_unique: failure_nodes,
    failure_tree_visits: failure_visits,
    reachable_from_cache_mb: (reachable_bytes / 1024.0 / 1024).round(1),
    reachable_objects: reachable_count,
    entries_by_kind: entries_by_kind.sort_by {|_, (n, _)| -n }.first(20).to_h,
  }

  # Drop analysis structures so they don't retain cache contents through the GC below
  entries = nil
  contexts = nil
  entries_by_kind = nil
  seen = nil
  stack = nil

  3.times { GC.start }
  rss_before = rss_kb.()
  live_before = GC.stat(:heap_live_slots)
  memsize_before = ObjectSpace.memsize_of_all

  checks.each do |c|
    c.cache.subtypes.clear
    c.cache.ground_subtypes.clear
  end
  3.times { GC.start }
  rss_after = rss_kb.()
  live_after = GC.stat(:heap_live_slots)
  memsize_after = ObjectSpace.memsize_of_all

  mem_summary.merge!(
    rss_before_clear_mb: (rss_before / 1024.0).round(1),
    rss_after_clear_mb: (rss_after / 1024.0).round(1),
    rss_freed_by_clear_mb: ((rss_before - rss_after) / 1024.0).round(1),
    memsize_freed_by_clear_mb: ((memsize_before - memsize_after) / 1024.0 / 1024).round(1),
    live_slots_freed_by_clear: live_before - live_after,
  )
  result[:memory] = mem_summary
end

if dump_path = ENV["DIAG_DUMP"]
  File.open(dump_path, "w") do |io|
    service.diagnostics.sort_by {|path, _| path.to_s }.each do |path, diags|
      diags.each do |diag|
        loc = diag.location
        line = loc ? (loc.respond_to?(:line) ? loc.line : loc.start_line) : "-"
        io.puts "#{path}:#{line}:#{diag.class}: #{diag.header_line}"
      end
    end
  end
end

if STATS
  stats = Steep::Subtyping::Stats.active or raise
  result[:counts] = {
    calls: stats.calls,
    reflexive_calls: stats.reflexive_calls,
    hits: stats.hits,
    toplevel_hits: stats.toplevel_hits,
    computes: stats.computes,
    toplevel_computes: stats.toplevel_computes,
    shortcuts: stats.shortcuts,
    context_misses: stats.context_misses,
    assumption_successes: stats.assumption_successes,
    toplevel_compute_time: stats.toplevel_compute_time.round(2),
  }
  cached_lookups = stats.calls - stats.shortcuts
  result[:hit_rate] = (stats.hits.to_f / cached_lookups).round(4) if cached_lookups > 0
end

if ENV["TIME_SHARE"] == "1"
  result[:subtyping_toplevel_calls] = SubtypingTimeShare::STATE[:calls]
  result[:subtyping_time] = SubtypingTimeShare::STATE[:time].round(2)
end

if STATS && ENV["KIND"] == "1"
  stats = Steep::Subtyping::Stats.active or raise
  result[:kinds] = stats.kinds.sort_by {|_, k| -k.calls }.first(30).map do |kind, k|
    {
      kind: kind,
      calls: k.calls,
      hits: k.hits,
      hit_rate: (k.hits.to_f / k.calls).round(3),
      computes: k.computes,
      tl_computes: k.toplevel_computes,
      tl_compute_time: k.toplevel_compute_time.round(3),
    }
  end

  result[:top_relations_by_calls] = stats.relations.sort_by {|_, r| -r.calls }.first(25).map do |rel, r|
    { relation: rel.to_s, calls: r.calls, hits: r.hits }
  end

  result[:distinct_relations] = stats.relations.size
end

puts JSON.pretty_generate(result)
