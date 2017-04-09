require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
task :build => :racc
task :test => :racc

rule /\.rb/ => ".y" do |t|
  sh "racc", "-v", "-o", "#{t.name}", "#{t.source}"
end

task :racc => "lib/steep/parser.rb"
