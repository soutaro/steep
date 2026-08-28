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
#
# Phases per target:
#   1. project types    types declared in the target's own signature files
#   2. library types    everything else in the environment (gems, stdlib, core)
#
# The report contains no type names, so it is safe to share -- except with
# VERBOSE_ERRORS, whose error messages usually name the failing types.

Encoding.default_external = Encoding::UTF_8

require "steep"
require "benchmark"
require "json"
require "objspace"

TARGET_NAMES = (ENV["TARGETS"] || "app").split(",").map(&:to_sym)
verbose_errors = ENV["VERBOSE_ERRORS"] == "1"

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

  sig_paths = loader.each_path_in_patterns(target.signature_pattern).to_a
  project_names = signature_service.type_names(paths: Set.new(sig_paths), env: env).to_set

  all_names = env.class_decls.keys + env.interface_decls.keys
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

  before = gc_memsize.()
  project_time, project_errors, project_error_tally = warm.(project_set)
  after_project = gc_memsize.()
  library_time, library_errors, library_error_tally = warm.(library_set)
  after_library = gc_memsize.()

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

  if verbose_errors
    result[:targets][target.name][:project_sig_paths] = sig_paths.size
    top_errors = ->(tally) { tally.sort_by {|_, count| -count }.first(20).to_h }
    result[:targets][target.name][:project_error_details] = top_errors.(project_error_tally)
    result[:targets][target.name][:library_error_details] = top_errors.(library_error_tally)
  end
end

puts JSON.pretty_generate(result)
