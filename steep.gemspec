# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'steep/version'

Gem::Specification.new do |spec|
  spec.name          = "steep"
  spec.version       = Steep::VERSION
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Gradual Typing for Ruby}
  spec.description   = %q{Gradual Typing for Ruby}
  spec.homepage      = "https://github.com/soutaro/steep"
  spec.license       = 'MIT'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/soutaro/steep"
  spec.metadata["changelog_uri"] = "https://github.com/soutaro/steep/blob/master/CHANGELOG.md"

  skip_dirs = %w(test spec features smoke sig gemfile_steep .github .vscode)
  skip_files = %w(Gemfile Gemfile.lock rbs_collection.steep.yaml rbs_collection.steep.lock.yaml)

  spec.files         = `git ls-files -z`.split("\x0").reject {|f|
    skip_dirs.any? {|dir| f.start_with?(dir + File::SEPARATOR) } || skip_files.include?(f)
  }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  if false
    # This is to let dependabot use 3.3, instead of 3.1.x.
    # They use `required_ruby_version=` method to detect the Ruby version they use.
    spec.required_ruby_version = ">= 3.3.0"
  end

  spec.required_ruby_version = '>= 3.2.0'

  spec.add_runtime_dependency "parser", ">= 3.2"
  spec.add_runtime_dependency "prism", ">= 0.25.0"
  spec.add_runtime_dependency "activesupport", ">= 5.1"
  spec.add_runtime_dependency "rainbow", ">= 2.2.2", "< 4.0"
  spec.add_runtime_dependency "listen", "~> 3.0"
  spec.add_runtime_dependency "language_server-protocol", ">= 3.17.0.4", "< 4.0"
  spec.add_runtime_dependency "rbs", "~> 4.0.0.dev"
  spec.add_runtime_dependency "concurrent-ruby", ">= 1.1.10"
  spec.add_runtime_dependency "terminal-table", ">= 2", "< 5"
  spec.add_runtime_dependency "securerandom", ">= 0.1"
  spec.add_runtime_dependency "json", ">= 2.1.0"
  spec.add_runtime_dependency "logger", ">= 1.3.0"
  spec.add_runtime_dependency "fileutils", ">= 1.1.0"
  spec.add_runtime_dependency "strscan", ">= 1.0.0"
  spec.add_runtime_dependency "csv", ">= 3.0.9"
  spec.add_runtime_dependency "uri", ">= 0.12.0"
  spec.add_runtime_dependency "mutex_m", ">= 0.3.0"
end
