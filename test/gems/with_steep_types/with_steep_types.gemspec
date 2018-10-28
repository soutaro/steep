# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "with_steep_types"
  spec.version       = "1.0.0"
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Test Gem}
  spec.description   = %q{Test Gem with steep_types metadata}
  spec.homepage      = "https://example.com"
  spec.license       = 'MIT'

  spec.files         = [
    "lib/with_steep_types.rb",
    "sig/with_steep_types.rbi"
  ]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "steep_types" => "sig"
  }
end
