#!/usr/bin/env ruby
# Estimates the boot cost of a shape-warming zygote process: builds the shapes
# of every class/module/interface in the environment ahead of time, like a
# zygote would before forking type check workers, and measures wall-clock time
# and memory growth.
#
# Run it in the project directory to measure (the Steepfile is loaded from the
# current directory):
#
#   bundle exec ruby "$(bundle info steep --path)/bin/shape_warmup_bench.rb"
#
# Env vars:
#   TARGETS=app,test    Steepfile targets to measure (default: app)
#   VERBOSE_ERRORS=1    Include the messages of shape building errors and the number of
#                       project signature files in the report
#   PHASES=1            Build all RBS definitions before the shapes, reporting the
#                       definition phase separately with time, memory, and GC time per
#                       phase -- the project/library times then measure the shape
#                       construction alone
#   STACKPROF=cpu       Profile the phases with stackprof (cpu, wall, or object) and
#                       print the report to stderr; STACKPROF_INTERVAL overrides the
#                       sampling interval, STACKPROF_OUT saves the raw dump to a file
#   WORKING_SET_OUT=p   Type check the target's source files instead of warming everything,
#                       and write the names of the types whose shapes were actually built to
#                       the file `p`; WORKING_SET_FILES=N checks only the first N files
#   WORKING_SET_IN=p    Warm only the types listed in the file `p`, instead of everything, to
#                       measure what a warmup limited to the working set costs
#   DEFINITIONS_ONLY=1  Warm the RBS definitions but not the shapes, to compare how much a
#                       partial warmup shares (implies PHASES=1)
#   FORK=N              After warming, fork N children that type check their share of the
#                       source files, like the type check workers do, and report the memory
#                       each one ends up owning privately -- the number that decides how many
#                       workers fit in memory. FORK_FILES=N limits the files checked.
#   NO_MAJOR_GC=1       Disable major GCs for the whole run with
#                       `GC.config(rgengc_allow_full_mark: false)` (Ruby 3.4+); the
#                       memory numbers then overestimate, because dead old objects
#                       are never collected
#
# Phases per target:
#   1. project types    types declared in the signature files and inline sources of the
#                       target and its groups
#   2. library types    everything else in the environment (gems, stdlib, core)
#
# The report contains no type names, so it is safe to share -- except with
# VERBOSE_ERRORS, whose error messages usually name the failing types. The stackprof
# report contains only Steep/RBS method names.

Encoding.default_external = Encoding::UTF_8

require "steep"
require "benchmark"
require "json"
require "objspace"

TARGET_NAMES = (ENV["TARGETS"] || "app").split(",").map(&:to_sym)
verbose_errors = ENV["VERBOSE_ERRORS"] == "1"
definitions_only = ENV["DEFINITIONS_ONLY"] == "1"
split_phases = ENV["PHASES"] == "1" || definitions_only
fork_count = ENV["FORK"]&.to_i
working_set_out = ENV["WORKING_SET_OUT"]
working_set_in = ENV["WORKING_SET_IN"]
stackprof_mode = ENV["STACKPROF"]&.to_sym

if stackprof_mode
  begin
    require "stackprof"
  rescue LoadError
    abort "STACKPROF needs the stackprof gem in the bundle"
  end
end

if ENV["NO_MAJOR_GC"] == "1"
  # Prototypes a boot that skips the major GCs while retaining almost everything --
  # minor GCs keep collecting the young garbage
  GC.respond_to?(:config) or abort "NO_MAJOR_GC needs Ruby 3.4+ (GC.config)"
  GC.config(rgengc_allow_full_mark: false)
end

GC.measure_total_time = true
gc_snap = -> { [GC.stat(:time), GC.stat(:major_gc_count), GC.stat(:minor_gc_count)] }
gc_delta = ->(snap) { gc_snap.().zip(snap).map {|now, was| now - was } }

if working_set_out
  # The shapes built during a type check are the ones a warmup actually has to provide
  TOUCHED = {} #: Hash[untyped, bool]
  Steep::Interface::Builder.class_eval do
    alias_method :object_shape_without_record, :object_shape
    def object_shape(type_name)
      TOUCHED[type_name] = true
      object_shape_without_record(type_name)
    end

    alias_method :singleton_shape_without_record, :singleton_shape
    def singleton_shape(type_name)
      TOUCHED[type_name] = true
      singleton_shape_without_record(type_name)
    end
  end
end

steepfile = Pathname.pwd + "Steepfile"
project = Steep::Project.new(steepfile_path: steepfile)
Steep::Project::DSL.parse(project, steepfile.read, filename: steepfile.to_s)

loader = Steep::Services::FileLoader.new(base_dir: project.base_dir)

service = nil
boot_time = Benchmark.realtime do
  service = Steep::Services::TypeCheckService.new(project: project)
end

changes = {}
project.targets.each do |target|
  loader.each_path_in_target(target) do |path|
    changes[path] ||= [Steep::Services::ContentChange.string((project.base_dir + path).read)]
  end
end
update_time = Benchmark.realtime { service.update(changes: changes) }

rss_mb = -> { File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024.0 }

# `Private_Dirty` is the memory a forked child does not share with its parent any more,
# so it is what each additional worker really costs
smaps_mb = ->(key) do
  if line = File.read("/proc/self/smaps_rollup")[/^#{key}:\s+(\d+) kB/]
    $1.to_i / 1024.0
  else
    0.0
  end
rescue Errno::ENOENT
  0.0
end
gc_memsize = -> { 2.times { GC.start }; ObjectSpace.memsize_of_all }

result = {
  boot: boot_time.round(2),
  update: update_time.round(2),
  targets: {},
}

targets = project.targets.select {|t| TARGET_NAMES.include?(t.name) }
raise "no matching targets: #{TARGET_NAMES}" if targets.empty?

targets.each do |target|
  signature_service = service.signature_services.fetch(target.name)
  subtyping = signature_service.current_subtyping

  unless subtyping
    result[:targets][target.name] = { error: "signature has errors; no subtyping available" }
    next
  end

  builder = subtyping.builder
  env = signature_service.latest_env

  # Signature and inline-source patterns of the groups don't appear in the target's own
  # patterns, so both levels have to be enumerated, like FileLoader#each_path_in_target
  sig_paths = [] #: Array[Pathname]
  collect_paths = ->(pattern) { loader.each_path_in_patterns(pattern) {|path| sig_paths << path } }
  target.groups.each do |group|
    collect_paths.(group.signature_pattern)
    collect_paths.(group.inline_source_pattern)
  end
  collect_paths.(target.signature_pattern)
  collect_paths.(target.inline_source_pattern)
  sig_paths.uniq!

  project_names = signature_service.type_names(paths: Set.new(sig_paths), env: env).to_set

  all_names = env.class_decls.keys + env.interface_decls.keys

  if working_set_in
    working_set = Set.new(File.readlines(working_set_in, chomp: true))
    all_names = all_names.select {|name| working_set.include?(name.to_s) }
  end

  project_set, library_set = all_names.partition {|name| project_names.include?(name) }

  warm = ->(names) do
    errors = 0
    error_tally = Hash.new(0)
    time = Benchmark.realtime do
      names.each do |name|
        begin
          if name.class?
            builder.object_shape(name)
            builder.singleton_shape(name)
          elsif name.interface?
            builder.object_shape(name)
          end
        rescue => exn
          errors += 1
          error_tally["#{exn.class}: #{exn.message}"[0, 200]] += 1 if verbose_errors
        end
      end
    end
    [time, errors, error_tally]
  end

  warm_definitions = ->(names) do
    definition_builder = builder.factory.definition_builder
    errors = 0
    time = Benchmark.realtime do
      names.each do |name|
        begin
          if name.class?
            definition_builder.build_instance(name)
            definition_builder.build_singleton(name)
          elsif name.interface?
            definition_builder.build_interface(name)
          end
        rescue => _
          errors += 1
        end
      end
    end
    [time, errors]
  end

  # Samples accumulate across the start/stop pairs, so the forced GCs of the memory
  # measurements between the phases stay out of the profile
  profile_phase = ->(callable) do
    if stackprof_mode
      interval = (ENV["STACKPROF_INTERVAL"] || (stackprof_mode == :object ? 100 : 1000)).to_i
      StackProf.start(mode: stackprof_mode, raw: false, interval: interval)
      begin
        callable.call
      ensure
        StackProf.stop
      end
    else
      callable.call
    end
  end

  if working_set_out
    source_paths = [] #: Array[Pathname]
    loader.each_path_in_target(target) do |path|
      source_paths << path if target.possible_source_file?(path)
    end
    if limit = ENV["WORKING_SET_FILES"]
      source_paths = source_paths.first(limit.to_i)
    end

    check_time = Benchmark.realtime do
      source_paths.each do |path|
        begin
          service.typecheck_source(path: path, target: target)
        rescue => _
        end
      end
    end

    File.write(working_set_out, TOUCHED.each_key.map(&:to_s).sort.join("\n"))

    result[:targets][target.name] = {
      checked_files: source_paths.size,
      check_time: check_time.round(2),
      environment_types: all_names.size,
      types_touched: TOUCHED.size,
      touched_ratio: (TOUCHED.size * 100.0 / all_names.size).round(1),
      rss_mb: rss_mb.().round(0),
    }
    next
  end

  if split_phases
    before_definitions = gc_memsize.()
    gc0 = gc_snap.()
    definitions_time, definitions_errors = profile_phase.(-> { warm_definitions.(all_names) })
    definitions_gc = gc_delta.(gc0)
  end

  before = gc_memsize.()

  if definitions_only
    project_time, project_errors, project_error_tally = 0.0, 0, {}
    library_time, library_errors, library_error_tally = 0.0, 0, {}
    project_gc = library_gc = [0, 0, 0]
    after_project = after_library = before
  else
    gc0 = gc_snap.()
    project_time, project_errors, project_error_tally = profile_phase.(-> { warm.(project_set) })
    project_gc = gc_delta.(gc0)
    after_project = gc_memsize.()
    gc0 = gc_snap.()
    library_time, library_errors, library_error_tally = profile_phase.(-> { warm.(library_set) })
    library_gc = gc_delta.(gc0)
    after_library = gc_memsize.()
  end

  compact_time = Benchmark.realtime { GC.compact }

  result[:targets][target.name] = {
    project_types: project_set.size,
    project_time: project_time.round(2),
    project_mb: ((after_project - before) / 1024.0 / 1024).round(1),
    project_errors: project_errors,
    library_types: library_set.size,
    library_time: library_time.round(2),
    library_mb: ((after_library - after_project) / 1024.0 / 1024).round(1),
    library_errors: library_errors,
    object_shape_cache: builder.object_shape_cache.size,
    singleton_shape_cache: builder.singleton_shape_cache.size,
    gc_compact_time: compact_time.round(2),
    rss_mb: rss_mb.().round(0),
  }

  if split_phases
    gc_report = ->(prefix, (ms, major, minor)) do
      { :"#{prefix}_gc_ms" => ms, :"#{prefix}_major_gc" => major, :"#{prefix}_minor_gc" => minor }
    end

    result[:targets][target.name].merge!(
      definitions_time: definitions_time.round(2),
      definitions_mb: ((before - before_definitions) / 1024.0 / 1024).round(1),
      definitions_errors: definitions_errors,
      **gc_report.(:definitions, definitions_gc),
      **gc_report.(:project, project_gc),
      **gc_report.(:library, library_gc),
    )
  end

  if fork_count
    # `Process.warmup` promotes everything to the old generation and compacts, so the pages
    # the children inherit are as stable as they get
    warmup_time = Benchmark.realtime { Process.warmup if Process.respond_to?(:warmup) }

    source_paths = [] #: Array[Pathname]
    loader.each_path_in_target(target) do |path|
      source_paths << path if target.possible_source_file?(path)
    end
    if limit = ENV["FORK_FILES"]
      source_paths = source_paths.first(limit.to_i)
    end

    parent_rss = rss_mb.()
    readers = source_paths.each_slice((source_paths.size.to_f / fork_count).ceil).map do |paths|
      reader, writer = IO.pipe

      fork do
        reader.close
        time = Benchmark.realtime do
          paths.each do |path|
            begin
              service.typecheck_source(path: path, target: target)
            rescue => _
            end
          end
        end
        writer.write(
          JSON.generate(
            files: paths.size,
            check_time: time.round(2),
            private_mb: smaps_mb.("Private_Dirty").round(1),
            shared_mb: smaps_mb.("Shared_Clean").round(1),
            rss_mb: rss_mb.().round(0)
          )
        )
        writer.close
        exit!(0)
      end

      writer.close
      reader
    end

    children = readers.map do |reader|
      json = reader.read
      reader.close
      JSON.parse(json, symbolize_names: true)
    end
    Process.waitall

    result[:targets][target.name].merge!(
      warmup_call_time: warmup_time.round(2),
      parent_rss_mb: parent_rss.round(0),
      workers: children.size,
      worker_check_time_max: children.map {|c| c[:check_time] }.max,
      worker_private_mb_avg: (children.sum {|c| c[:private_mb] } / children.size).round(1),
      worker_private_mb_max: children.map {|c| c[:private_mb] }.max,
      worker_rss_mb_avg: (children.sum {|c| c[:rss_mb] } / children.size).round(0)
    )
  end

  if verbose_errors
    result[:targets][target.name][:project_sig_paths] = sig_paths.size
    top_errors = ->(tally) { tally.sort_by {|_, count| -count }.first(20).to_h }
    result[:targets][target.name][:project_error_details] = top_errors.(project_error_tally)
    result[:targets][target.name][:library_error_details] = top_errors.(library_error_tally)
  end
end

if stackprof_mode
  profile = StackProf.results
  if profile
    File.binwrite(ENV["STACKPROF_OUT"], Marshal.dump(profile)) if ENV["STACKPROF_OUT"]
    StackProf::Report.new(profile).print_text(false, 30, nil, nil, nil, nil, $stderr)
  end
end

puts JSON.pretty_generate(result)
