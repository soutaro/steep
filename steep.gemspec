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

  spec.files         = `git ls-files -z`.split("\x0").reject {|f|
    f.match(%r{^(test|spec|features)/})
  }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 3.0.0'

  spec.add_runtime_dependency "parser", ">= 3.1"
  spec.add_runtime_dependency "activesupport", ">= 5.1"
  spec.add_runtime_dependency "rainbow", ">= 2.2.2", "< 4.0"
  spec.add_runtime_dependency "listen", "~> 3.0"
  spec.add_runtime_dependency "language_server-protocol", ">= 3.15", "< 4.0"
  spec.add_runtime_dependency "rbs", ">= 3.1.0"
  spec.add_runtime_dependency "concurrent-ruby", ">= 1.1.10"
  spec.add_runtime_dependency "terminal-table", ">= 2", "< 4"
  spec.add_runtime_dependency "securerandom", ">= 0.1"
  spec.add_runtime_dependency "json", ">= 2.1.0"
  spec.add_runtime_dependency "logger", ">= 1.3.0"
  spec.add_runtime_dependency "fileutils", ">= 1.1.0"
  spec.add_runtime_dependency "strscan", ">= 1.0.0"
  spec.add_runtime_dependency "csv", ">= 3.0.9"
end
