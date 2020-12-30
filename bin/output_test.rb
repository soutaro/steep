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

success = true

test_dirs.each do |dir|
  test = dir + "test.yaml"

  next unless test.file?

  puts "Running test #{dir}..."

  content = YAML.load_file(test)

  command = content["command"] || "steep check"
  puts "  command: #{command}"

  output, _ = Open3.capture2(command, chdir: dir.to_s)

  if @verbose
    puts "  Raw output:"
    output.split(/\n/).each do |line|
      puts "  > #{line.chomp}"
    end
  end

  diagnostics = output.split(/\n\n/).each.with_object({}) do |d, hash|
    if d =~ /\A([^:]+):\d+:\d+:/
      path = $1
      hash[path] ||= []
      hash[path] << (d.chomp + "\n")
    end
  end

  content["test"].each do |path, test|
    puts "  Checking: #{path}..."

    fail_expected = test["fail"] || false

    expected_diagnostics = test["diagnostics"]
    reported_diagnostics = (diagnostics[path] || [])

    puts "    # of expected: #{expected_diagnostics.size}, # of reported: #{reported_diagnostics.size}"

    unexpected_diagnostics = reported_diagnostics.reject {|d| expected_diagnostics.include?(d) }
    missing_diagnostics = expected_diagnostics.reject {|d| reported_diagnostics.include?(d) }

    unexpected_diagnostics.each do |d|
      puts "    Unexpected diagnostics:"
      d.split(/\n/).each do |line|
        puts "      + #{line.chomp}"
      end
    end

    missing_diagnostics.each do |d|
      puts "    Missing diagnostics:"
      d.split(/\n/).each do |line|
        puts "      - #{line.chomp}"
      end
    end

    if unexpected_diagnostics.empty? && missing_diagnostics.empty?
      puts "    👍"
    else
      if fail_expected
        puts "    🚨 (expected failure)"
      else
        puts "    🚨"
        success = false
      end
    end
  end
end

if success
  puts "All tests ok! 👏"
else
  puts "Errors detected! 🤮"
  exit 1
end
