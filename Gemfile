source 'https://rubygems.org'

# Specify your gem's dependencies in steep.gemspec
gemspec

gem "rake"
gem "minitest", "~> 5.16"
gem "minitest-hooks"
group :stackprof, optional: true do
  gem "stackprof"
end
gem 'minitest-slow_test'
gem "rbs", git: "https://github.com/ruby/rbs.git", branch: "master"

group :ide, optional: true do
  gem "ruby-debug-ide"
  gem "debase", ">= 0.2.5.beta2"
end
