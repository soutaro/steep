require "pathname"
require "yaml"
require "open3"
require "tempfile"

if ARGV.empty?
  test_dirs = (Pathname(__dir__) + "../smoke").children
else
  test_dirs = ARGV.map {|p| Pathname.pwd + p }
end

test_dirs.each do |dir|
  test = dir + "test.yaml"

  if test.file?
    content = YAML.load_file(test)
  else
    content = { "test" => {} }
  end

  puts "Rebaselining #{dir}..."

  command = content["command"] || "steep check"
  puts "  command: #{command}"

  output, _ = Open3.capture2(command, chdir: dir.to_s)

  diagnostics = output.split(/\n\n/).each.with_object({}) do |message, hash|
    if message =~ /\A([^:]+):\d+:\d+:/
      path = $1
      hash[path] ||= { "diagnostics" => [] }
      hash[path]["diagnostics"] << message.chomp + "\n"
    end
  end

  content["test"].each_key do |path|
    unless diagnostics.key?(path)
      diagnostics[path] = { "diagnostics" => [] }
    end
  end

  content["test"] = diagnostics.keys.sort.each.with_object({}) do |key, hash|
    hash[key] = diagnostics[key]
  end

  test.open("w") do |io|
    YAML.dump(content, io, header: false)
  end
end
