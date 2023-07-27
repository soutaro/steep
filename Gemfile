source 'https://rubygems.org'

# Specify your gem's dependencies in steep.gemspec
gemspec

gem "rake"
gem "minitest", "~> 5.19"
gem "minitest-hooks"
group :stackprof, optional: true do
  gem "stackprof"
end
gem 'minitest-slow_test'

group :development do
  gem "ruby-lsp", require: false
end
