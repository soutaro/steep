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
#   CACHE_STATS=1       count cache hits/misses in Check#check_type (adds overhead;
#                       do not trust timing from a stats run)
#   TIME_SHARE=1        measure wall-clock time spent inside top-level check_type
#                       calls, to see the share of subtyping in type checking
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

if STATS
  # Mirrors the branch logic at the top of Check#check_type to classify each
  # call, then delegates to the original implementation.
  module CacheStatsCounter
    COUNTS = Hash.new(0)

    def check_type(relation)
      counts = COUNTS
      counts[:calls] += 1

      begin
        if assumptions.size > Steep::Subtyping::Check::ABORT_LIMIT
          counts[:loop_abort] += 1
        else
          bounds = cache_bounds(relation)
          cached = cache[relation, @self_type, @instance_type, @class_type, bounds]
          if cached
            fvs = relation.sub_type.free_variables + relation.super_type.free_variables
            if fvs.none? {|var| var.is_a?(Symbol) && constraints.unknown?(var) }
              counts[:hit] += 1
              counts[:hit_toplevel] += 1 if assumptions.empty?
            elsif assumptions.member?(relation)
              counts[:assumption] += 1
            else
              counts[:compute_after_discarded_hit] += 1
            end
          elsif assumptions.member?(relation)
            counts[:assumption] += 1
          else
            counts[:compute_miss] += 1
            counts[:miss_toplevel] += 1 if assumptions.empty?
          end
        end
      rescue => _
        counts[:classify_error] += 1
      end

      super
    end
  end
  Steep::Subtyping::Check.prepend(CacheStatsCounter)
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

  sig_time = Benchmark.realtime do
    sig_paths.each {|path| service.validate_signature(path: path, target: target) }
  end

  src_time = Benchmark.realtime do
    src_paths.each {|path| service.typecheck_source(path: path, target: target) }
  end

  check = service.signature_services.fetch(target.name).current_subtyping
  result[:phases][target.name] = {
    sig_files: sig_paths.size,
    sig_time: sig_time.round(2),
    src_files: src_paths.size,
    src_time: src_time.round(2),
    cache_entries: check && check.cache.subtypes.size,
  }
end

diagnostics_count = service.diagnostics.sum {|_, diags| diags.size }
result[:diagnostics] = diagnostics_count

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
  counts = CacheStatsCounter::COUNTS
  result[:counts] = counts
  computes = counts[:compute_miss] + counts[:compute_after_discarded_hit]
  lookups = counts[:hit] + counts[:assumption] + computes
  result[:hit_rate] = (counts[:hit].to_f / lookups).round(4) if lookups > 0
end

if ENV["TIME_SHARE"] == "1"
  result[:subtyping_toplevel_calls] = SubtypingTimeShare::STATE[:calls]
  result[:subtyping_time] = SubtypingTimeShare::STATE[:time].round(2)
end

puts JSON.pretty_generate(result)
