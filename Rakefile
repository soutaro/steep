require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
task :build => :parser
task :test => :parser
task :install => [:reset, :parser]

task :parser do
  Dir.chdir "vendor/ruby-signature" do
    sh "bundle exec rake parser"
  end
end

task :reset do
  sh "git submodule update -f --init"
end

task :smoke do
  sh "bundle", "exec", "bin/smoke_runner.rb", *Dir.glob("smoke/*")
end
