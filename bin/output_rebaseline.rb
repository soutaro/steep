require "pathname"
require "yaml"
require "open3"
require "tempfile"

if ARGV.empty?
  test_dirs = (Pathname(__dir__) + "../smoke").children
else
  test_dirs = ARGV.map {|p| Pathname.pwd + p }
end

failed_tests = []

test_dirs.each do |dir|
  puts "Rebaselining #{dir}..."

  command = %w(steep check --save-expectations=test_expectations.yml)
  puts "  command: #{command.join(" ")}"

  output, status = Open3.capture2(*command, chdir: dir.to_s)

  unless status.success?
    puts "Error!!! 👺"
    failed_tests << dir.basename
  end
end

if failed_tests.empty?
  puts "Successfully updated output expectations! 🤡"
else
  puts "Failed to update the following tests! 💀"
  puts "  #{failed_tests.join(", ")}"
  exit 1
end
