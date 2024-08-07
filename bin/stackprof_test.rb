#!/usr/bin/env ruby

require "stackprof"

mode = (ENV["STEEP_STACKPROF_MODE"] || :cpu).to_sym
out = ENV["STEEP_STACKPROF_OUT"] || "tmp/stackprof-#{mode}-test.dump"
interval = ENV["STEEP_STACKPROF_INTERVAL"]&.to_i || 1000

STDERR.puts "Running profiler: mode => #{mode}, out => #{out}"
StackProf.run(mode: mode, out: out, raw: true, interval: interval) do
  # 10.times do
  #   1_000.times do
  #     Array.new(1_000_000)
  #   end
  #   sleep 0.1
  # end

  sleep 5
end
