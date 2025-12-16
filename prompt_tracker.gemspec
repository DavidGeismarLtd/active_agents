require_relative "lib/prompt_tracker/version"

Gem::Specification.new do |spec|
  spec.name        = "prompt_tracker"
  spec.version     = PromptTracker::VERSION
  spec.authors     = [ "David Geismar" ]
  spec.email       = [ "davidgeismar@yunoo.io" ]
  spec.homepage    = "https://github.com/DavidGeismarLtd/PromptTracker"
  spec.summary     = "Rails engine for managing and tracking LLM prompts"
  spec.description = "A comprehensive Rails 7.2 engine for managing, tracking, and analyzing LLM prompts with evaluation, A/B testing, and analytics."
  spec.license     = "MIT"

  # Metadata
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/DavidGeismarLtd/PromptTracker"
  spec.metadata["changelog_uri"] = "https://github.com/DavidGeismarLtd/PromptTracker/blob/master/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.2.3"
  spec.add_dependency "kaminari", "~> 1.2"
  spec.add_dependency "groupdate", "~> 6.0"
  spec.add_dependency "liquid", "~> 5.5"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"
end
