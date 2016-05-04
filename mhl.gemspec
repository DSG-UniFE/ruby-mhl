# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mhl/version'

Gem::Specification.new do |spec|
  spec.name          = 'mhl'
  spec.version       = MHL::VERSION
  spec.authors       = ['Mauro Tortonesi']
  spec.email         = ['mauro.tortonesi@unife.it']
  spec.description   = %q{A Ruby Metaheuristics library}
  spec.summary       = %q{A scientific library for Ruby that provides several metaheuristics}
  spec.homepage      = 'https://github.com/mtortonesi/ruby-mhl'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/).reject{|x| x == '.gitignore' }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'bitstring'
  spec.add_dependency 'concurrent-ruby', '~> 1.0'
  spec.add_dependency 'erv'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
