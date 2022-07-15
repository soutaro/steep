require "bundler/gem_tasks"
require "rake/testtask"

if ENV["VSCODE_CWD"]
  require "minitest"
  Minitest.seed = Time.now.to_i
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test

namespace :test do
  desc "Run output test"
  task :output do
    sh "ruby", "bin/output_test.rb"
  end
end
