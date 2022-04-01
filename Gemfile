source 'https://rubygems.org'

# Specify your gem's dependencies in steep.gemspec
gemspec

gem "with_steep_types", path: "test/gems/with_steep_types"
gem "without_steep_types", path: "test/gems/without_steep_types"

gem "rake"
gem "minitest", "~> 5.15"
gem "minitest-hooks"
group :stackprof, optional: true do
  gem "stackprof"
end
gem 'minitest-slow_test'
