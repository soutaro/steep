# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "without_steep_types"
  spec.version       = "1.0.0"
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Test Gem2}
  spec.description   = %q{Test Gem2 without steep_types metadata}
  spec.homepage      = "https://example.com"
  spec.license       = 'MIT'

  spec.files         = [
    "lib/without_steep_types.rb",
  ]
  spec.require_paths = ["lib"]
end
