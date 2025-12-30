source 'https://rubygems.org'

# Specify your gem's dependencies in steep.gemspec
gemspec

gem "rake"
gem "minitest", "~> 6.0"
gem "minitest-hooks"
gem 'minitest-slow_test'

group :development, optional: true do
  gem "stackprof"
  gem "debug", require: false, platform: :mri
  gem "vernier", "~> 1.5", require: false, platform: :mri
  gem "memory_profiler"
  gem "majo"
end

# gem "rbs", path: "../rbs"
gem "rbs", git: "https://github.com/ruby/rbs.git", branch: "master"
