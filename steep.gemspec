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

  spec.files         = `git ls-files -z`.split("\x0").reject {|f|
    f.match(%r{^(test|spec|features)/})
  }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.6.0'

  spec.add_development_dependency "bundler", ">= 1.13"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "racc", "~> 1.4"
  spec.add_development_dependency "minitest-reporters", "~> 1.3.6"
  spec.add_development_dependency "minitest-hooks", "~> 1.5.0"

  spec.add_runtime_dependency "parser", "~> 2.7.0"
  spec.add_runtime_dependency "ast_utils", "~> 0.3.0"
  spec.add_runtime_dependency "activesupport", ">= 5.1"
  spec.add_runtime_dependency "rainbow", ">= 2.2.2", "< 4.0"
  spec.add_runtime_dependency "listen", "~> 3.1"
  spec.add_runtime_dependency "pry", ">= 0.12.2", "< 0.14.0"
  spec.add_runtime_dependency "language_server-protocol", "~> 3.14.0.2"
  spec.add_runtime_dependency "rbs", "~> 0.3.1"
end
