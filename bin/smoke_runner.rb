#!/usr/bin/env ruby

require "pathname"

$LOAD_PATH << Pathname(__dir__) + "../lib"

require "steep"
require "steep/cli"
require "rainbow"
require "optparse"

verbose = false

OptionParser.new do |opts|
  opts.on("-v", "--verbose") do verbose = true end
end.parse!(ARGV)

Expectation = Struct.new(:line, :message, :path, :starts) do
  attr_accessor :prefix_test
end

failed = false

ARGV.each do |arg|
  dir = Pathname(arg)
  puts "🏇 Running smoke test in #{dir}..."

  rb_files = []
  expectations = []
  allowed_paths = []
  
  dir.children.each do |file|
    if file.extname == ".rb"
      buffer = ::Parser::Source::Buffer.new(file.to_s)
      buffer.source = file.read
      parser = ::Parser::Ruby27.new

      _, comments, _ = parser.tokenize(buffer)
      comments.each do |comment|
        src = comment.text.gsub(/\A#\s*/, '')

        if src =~ /!expects\*(@(\+\d+))?/
          offset = $2&.to_i || 1
          message = src.gsub!(/\A!expects\*(@\+\d+)? +/, '')
          line = comment.location.line

          expectations << Expectation.new(line+offset, message, file.relative_path_from(dir)).tap {|e| e.prefix_test = true }
        end

        if src =~ /!expects(@(\+\d+))?/
          offset = $2&.to_i || 1
          message = src.gsub!(/\A!expects(@\+\d+)? +/, '')
          line = comment.location.line

          expectations << Expectation.new(line+offset, message, file.relative_path_from(dir))
        end

        if src =~ /ALLOW FAILURE/
          allowed_paths << file.relative_path_from(dir)
        end
      end

      rb_files << file
    end
  end

  stderr = StringIO.new
  stdout = StringIO.new

  begin
    Rainbow.enabled = false
    Dir.chdir(arg) do
      Steep::Drivers::Check.new(stdout: stdout, stderr: stderr).run
    end
  rescue => exn
    puts "ERROR: #{exn.inspect}"
    exn.backtrace.each do |loc|
      puts "  #{loc}"
    end

    failed = true
  ensure
    Rainbow.enabled = true
  end

  if verbose
    stdout.string.each_line do |line|
      puts "stdout> #{line.chomp}"
    end

    stderr.string.each_line do |line|
      puts "stderr> #{line.chomp}"
    end
  end

  lines = stdout.string.each_line.to_a.map(&:chomp).reject {|line| line =~ /\bFallbackAny\b/ }

  expectations.each do |expectation|
    deleted = lines.reject! do |string|
      if expectation.prefix_test
        string =~ /\A#{Regexp.escape(expectation.path.to_s)}:#{expectation.line}:\d+: #{Regexp.quote expectation.message}/
      else
        string =~ /\A#{Regexp.escape(expectation.path.to_s)}:#{expectation.line}:\d+: #{Regexp.quote expectation.message} \(/
      end
    end

    unless deleted
      allowed = allowed_paths.any? {|path| path == expectation.path }
      message = Rainbow("  💀 Expected error not found: #{expectation.path}:#{expectation.line}:#{expectation.message}")
      if allowed
        puts message.yellow
      else
        puts message.red
        failed = true
      end
    end
  end

  unless lines.empty?
    lines.each do |line|
      if line =~ /\A([^:]+):\d+:\d+:/
        message = Rainbow("  🤦‍♀️ Unexpected error found: #{line}")

        if allowed_paths.include?(Pathname($1))
          puts message.yellow
        else
          puts message.red
          failed = true
        end
      end
    end
  end
end

if failed
  exit(1)
else
  puts Rainbow("All smoke test pass 😆").blue
end
