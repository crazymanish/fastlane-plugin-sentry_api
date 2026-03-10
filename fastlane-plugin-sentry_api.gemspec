lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/sentry_api/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-sentry_api'
  spec.version       = Fastlane::SentryApi::VERSION
  spec.author        = 'crazymanish'
  spec.email         = 'i.am.manish.rathi@gmail.com'

  spec.summary       = 'Fastlane plugin for Sentry APIs - crash-free rates, TTID percentiles, issue tracking, and SLO reports'
  spec.homepage      = "https://github.com/crazymanish/fastlane-plugin-sentry_api"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"] + %w(README.md LICENSE)
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.required_ruby_version = '>= 2.6'

  # Don't add a dependency to fastlane or fastlane_re
  # since this would cause a circular dependency

  # spec.add_dependency 'your-dependency', '~> 1.0.0'
end
