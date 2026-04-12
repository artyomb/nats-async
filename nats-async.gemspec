# frozen_string_literal: true

require_relative "lib/version"

Gem::Specification.new do |s|
  s.name        = "nats-async"
  s.version     = NatsAsync::VERSION
  s.summary     = "Async NATS connector"
  s.description = "Lightweight async Ruby connector for NATS"
  s.authors     = ["Artem Borodkin"]
  s.email       = ["author@email.address"]
  s.files       = Dir["{examples,lib,spec}/**/*", ".github/workflows/*", ".rspec", ".rubocop.yml", "README.md", "Rakefile"]

  s.require_paths = ["lib"]
  s.homepage      = "https://rubygems.org/gems/nats-async"
  s.license       = "Nonstandard"
  s.metadata      = {"source_code_uri" => "https://github.com/artyomb/nats-async"}

  s.required_ruby_version = ">= " + File.read(File.expand_path(".ruby-version", __dir__)).strip

  s.add_runtime_dependency "async", "~> 2.36"
  s.add_runtime_dependency "base64", "~> 0.3"
  s.add_runtime_dependency "console", "~> 1.34"
  s.add_runtime_dependency "io-endpoint", "~> 0.17"
  s.add_runtime_dependency "io-stream", "~> 0.11"
  s.add_runtime_dependency "nkeys", ">= 0.1", "< 1.0"

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.10"
  s.add_development_dependency "rubocop", "~> 1.12"
  s.add_development_dependency "rubocop-rake", "~> 0.6.0"
  s.add_development_dependency "rubocop-rspec", "~> 2.14.2"
  s.add_development_dependency "rspec_junit_formatter", "~> 0.5.1"
end
