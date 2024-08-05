require "objspace"

class MemProf
  attr_reader :generation

  def initialize
  end

  def self.trace(io: STDOUT, &block)
    profiler = MemProf.new
    profiler.start

    begin
      ret = yield
    rescue
      ObjectSpace.trace_object_allocations_stop
      ObjectSpace.trace_object_allocations_clear
      raise
    end

    allocated, retained, collected = profiler.stop

    counts = {}
    collected.each do |id, entry|
      counts[entry] ||= 0
      counts[entry] += 1
    end

    counts.keys.sort_by {|entry| -counts[entry] }.take(200).each do |entry|
      count = counts.fetch(entry)
      io.puts "#{entry[0]},#{entry[1]},#{entry[2]},#{count}"
    end

    STDERR.puts "Total allocated: #{allocated.size}"
    STDERR.puts "Total retained: #{retained.size}"
    STDERR.puts "Total collected: #{collected.size}"

    ret
  end

  def start
    GC.disable
    3.times { GC.start }
    GC.start

    @generation = GC.count
    ObjectSpace.trace_object_allocations_start
  end

  def stop
    ObjectSpace.trace_object_allocations_stop

    allocated = objects()
    retained = {}

    GC.enable
    GC.start
    GC.start
    GC.start

    ObjectSpace.each_object do |obj|
      next unless ObjectSpace.allocation_generation(obj) == generation
      if o = allocated[obj.__id__]
        retained[obj.__id__] = o
      end
    end

    # ObjectSpace.trace_object_allocations_clear

    collected = {}
    allocated.each do |id, state|
      collected[id] = state unless retained.key?(id)
    end

    [allocated, retained, collected]
  end

  def objects(hash = {})
    ObjectSpace.each_object do |obj|
      next unless ObjectSpace.allocation_generation(obj) == generation

      file = ObjectSpace.allocation_sourcefile(obj) || "(no name)"
      line = ObjectSpace.allocation_sourceline(obj)
      klass = object_class(obj)

      hash[obj.__id__] = [file, line, klass]
    end

    hash
  end

  KERNEL_CLASS_METHOD = Kernel.instance_method(:class)
  def object_class(obj)
    klass = obj.class rescue nil

    unless Class === klass
      # attempt to determine the true Class when .class returns something other than a Class
      klass = KERNEL_CLASS_METHOD.bind_call(obj)
    end
    klass
  end
end
