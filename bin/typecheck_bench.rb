#!/usr/bin/env ruby
# Measures the type checking of the source files of Steepfile targets in one
# process, after the signatures are loaded, to compare the type checking
# itself between versions of Steep -- the wall-clock time of `steep check`
# also includes the boot and the scheduling of the workers.
#
# Run it in the project directory to measure (the Steepfile is loaded from the
# current directory):
#
#   bundle exec ruby "$(bundle info steep --path)/bin/typecheck_bench.rb"
#
# The script needs nothing but the `steep` gem in the bundle, so a copy of it
# can measure an older Steep that doesn't have it: save a copy, check out the
# older revision in the path source of the bundle, and run the copy.
#
# Env vars:
#   TARGETS=app,test    Steepfile targets to check (default: app)
#   FILES=N             Check only the first N source files of each target
#   STACKPROF=cpu       Profile the type checking with stackprof (cpu, wall, or object)
#                       and print the report to stderr; STACKPROF_INTERVAL overrides the
#                       sampling interval, STACKPROF_OUT saves the raw dump to a file
#
# The report contains no file or type names, so it is safe to share. The
# stackprof report contains only Steep/RBS method names.

Encoding.default_external = Encoding::UTF_8

require "steep"
require "benchmark"
require "json"
require "objspace"

TARGET_NAMES = (ENV["TARGETS"] || "app").split(",").map(&:to_sym)
file_limit = ENV["FILES"]&.to_i
stackprof_mode = ENV["STACKPROF"]&.to_sym

if stackprof_mode
  begin
    require "stackprof"
  rescue LoadError
    abort "STACKPROF needs the stackprof gem in the bundle"
  end
end

GC.measure_total_time = true
gc_snap = -> { [GC.stat(:time), GC.stat(:major_gc_count), GC.stat(:minor_gc_count)] }
gc_delta = ->(snap) { gc_snap.().zip(snap).map {|now, was| now - was } }
gc_memsize = -> { 2.times { GC.start }; ObjectSpace.memsize_of_all }
rss_mb = -> { File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024.0 }

steepfile = Pathname.pwd + "Steepfile"
project = Steep::Project.new(steepfile_path: steepfile)
Steep::Project::DSL.parse(project, steepfile.read, filename: steepfile.to_s)

loader = Steep::Services::FileLoader.new(base_dir: project.base_dir)
service = Steep::Services::TypeCheckService.new(project: project)

changes = {}
project.targets.each do |target|
  loader.each_path_in_target(target) do |path|
    changes[path] ||= [Steep::Services::ContentChange.string((project.base_dir + path).read)]
  end
end
update_time = Benchmark.realtime { service.update(changes: changes) }

result = {
  update: update_time.round(2),
  targets: {},
}

targets = project.targets.select {|t| TARGET_NAMES.include?(t.name) }
raise "no matching targets: #{TARGET_NAMES}" if targets.empty?

profile = ->(callable) do
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

targets.each do |target|
  unless service.signature_services.fetch(target.name).current_subtyping
    result[:targets][target.name] = { error: "signature has errors; no subtyping available" }
    next
  end

  source_paths = [] #: Array[Pathname]
  loader.each_path_in_target(target) do |path|
    source_paths << path if target.possible_source_file?(path)
  end
  source_paths = source_paths.first(file_limit) if file_limit

  before = gc_memsize.()
  gc0 = gc_snap.()
  allocated0 = GC.stat(:total_allocated_objects)
  errors = 0

  check_time = Benchmark.realtime do
    profile.(-> do
      source_paths.each do |path|
        begin
          service.typecheck_source(path: path, target: target)
        rescue => _
          errors += 1
        end
      end
    end)
  end

  allocated = GC.stat(:total_allocated_objects) - allocated0
  gc_ms, major_gc, minor_gc = gc_delta.(gc0)
  after = gc_memsize.()

  diagnostics = source_paths.sum {|path| service.diagnostics.fetch(path, []).size }

  result[:targets][target.name] = {
    files: source_paths.size,
    check_time: check_time.round(2),
    diagnostics: diagnostics,
    errors: errors,
    allocated_objects: allocated,
    gc_ms: gc_ms,
    major_gc: major_gc,
    minor_gc: minor_gc,
    retained_mb: ((after - before) / 1024.0 / 1024).round(1),
    rss_mb: rss_mb.().round(0),
  }
end

if stackprof_mode
  profile = StackProf.results
  if profile
    File.binwrite(ENV["STACKPROF_OUT"], Marshal.dump(profile)) if ENV["STACKPROF_OUT"]
    StackProf::Report.new(profile).print_text(false, 30, nil, nil, nil, nil, $stderr)
  end
end

puts JSON.pretty_generate(result)
