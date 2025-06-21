# This is a sample .rake file to test Rake::DSL top-level context

desc "Run tests"
task :test do
  puts "Running tests..."
end

desc "Build the project"
task :build => :test do
  puts "Building project..."
end

# Test that Rake DSL methods are available at top-level
namespace :sample do
  desc "Sample task"
  task :hello do
    puts "Hello from rake task!"
    1 + ""
  end
end
