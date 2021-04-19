require "pathname"
require "yaml"
require "open3"
require "tempfile"
require "optparse"

OptionParser.new do |opts|
  opts.on("--verbose", "-v") { @verbose = true }
end.parse!(ARGV)

if ARGV.empty?
  test_dirs = (Pathname(__dir__) + "../smoke").children
else
  test_dirs = ARGV.map {|p| Pathname.pwd + p }
end

failed_tests = []

ALLOW_FAILURE = ["diagnostics-ruby-unsat"]

test_dirs.each do |dir|
  puts "Running test #{dir}..."

  unless (dir + "test_expectations.yml").file?
    puts "Skipped ⛹️‍♀️"
    next
  end

  command = %w(steep check --with-expectations=test_expectations.yml)
  puts "  command: #{command.join(" ")}"

  output, status = Open3.capture2(*command, chdir: dir.to_s)

  unless status.success?
    unless ALLOW_FAILURE.include?(dir.basename.to_s)
      failed_tests << dir.basename
      puts "  Failed! 🤕"
    else
      puts "  Failed! 🤕 (ALLOW_FAILURE)"
    end
  else
    puts "  Succeed! 👍"
  end

  if @verbose
    puts "  Raw output:"
    output.split(/\n/).each do |line|
      puts "  > #{line.chomp}"
    end
  end
end

if failed_tests.empty?
  puts "All tests ok! 👏"
else
  puts "Errors detected! 🤮"
  puts "  #{failed_tests.join(", ")}"
  exit 1
end
