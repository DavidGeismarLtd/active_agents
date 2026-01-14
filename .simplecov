# frozen_string_literal: true

# SimpleCov configuration for PromptTracker
# Tracks test coverage for both Minitest and RSpec

SimpleCov.start "rails" do
  # Coverage directory
  coverage_dir "coverage"

  # Minimum coverage threshold
  # Set to current coverage level - gradually increase as more tests are added
  minimum_coverage 70

  # Track all files in app/
  track_files "app/**/*.rb"

  # Add groups for better organization
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Helpers", "app/helpers"
  add_group "Evaluators", "app/services/prompt_tracker/evaluators"

  # Exclude files from coverage
  add_filter "/test/"
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "app/channels/"
  add_filter "app/mailers/"

  # Merge results from multiple test runs (Minitest + RSpec)
  use_merging true
  merge_timeout 3600 # 1 hour

  # Enable branch coverage (Ruby 2.5+)
  enable_coverage :branch

  # Formatter - generate both HTML and terminal output
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
end
