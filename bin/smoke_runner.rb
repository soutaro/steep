#!/usr/bin/env ruby

require "pathname"

$LOAD_PATH << Pathname(__dir__) + "../lib"

require "steep"
require "rainbow"

Expectation = Struct.new(:line, :message)

failed = false

ARGV.each do |arg|
  dir = Pathname(arg)
  puts "Running smoke test in #{dir}..."

  rb_files = []
  expectations = []

  dir.children.each do |file|
    if file.extname == ".rb"
      buffer = ::Parser::Source::Buffer.new(file.to_s)
      buffer.source = file.read
      parser = ::Parser::CurrentRuby.new

      _, comments, _ = parser.tokenize(buffer)
      comments.each do |comment|
        src = comment.text.gsub(/\A#\s*/, '')

        if src =~ /!expects/
          message = src.gsub!(/\A!expects +/, '')
          line = comment.location.line

          expectations << Expectation.new(line+1, message)
        end
      end

      rb_files << file
    end
  end

  stderr = StringIO.new
  stdout = StringIO.new

  builtin = Pathname(__dir__) + "../sig"
  driver = Steep::Drivers::Check.new(source_paths: rb_files,
                                     signature_dirs: [builtin, dir],
                                     stdout: stdout,
                                     stderr: stderr)

  driver.run

  lines = stdout.string.each_line.to_a.map(&:chomp)

  expectations.each do |expectation|
    deleted = lines.reject! do |string|
      string =~ /:#{expectation.line}:\d+: #{expectation.message}\Z/
    end

    unless deleted
      puts Rainbow("  💀 Expected error not found: #{expectation.line-1}:#{expectation.message}").red
      failed = true
    end
  end

  unless lines.empty?
    lines.each do |line|
      puts Rainbow("  🤦‍♀️ Unexpected error found: #{line}").red
    end
    failed = true
  end
end

if failed
  exit(1)
else
  puts Rainbow("All smoke test pass 😆").blue
end
