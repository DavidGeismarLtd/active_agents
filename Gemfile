source "https://rubygems.org"

# Specify your gem's dependencies in prompt_tracker.gemspec.
gemspec

gem "puma"

gem "pg", "~> 1.5"

gem "sprockets-rails"

gem "pry-byebug"
gem "ostruct" # Required for Ruby 3.5+ compatibility

# LLM API clients - unified interface for all providers
gem "ruby_llm"

# OpenAI gem for Assistants API (not covered by ruby_llm)
gem "ruby-openai", "~> 7.0"

# Background job processing
gem "sidekiq", "~> 7.0"
gem "redis", "~> 5.0"

# Hotwire's SPA-like page accelerator and real-time updates
gem "turbo-rails"
gem "stimulus-rails"

# Import maps for JavaScript modules
gem "importmap-rails"

# Development
group :development do
  gem "annotate", "~> 3.2"
  gem "dotenv-rails"
end

# Testing
group :development, :test do
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
end

group :test do
  gem "shoulda-matchers", "~> 6.0"
  gem "database_cleaner-active_record", "~> 2.1"
  gem "simplecov", require: false
  gem "webmock", "~> 3.19"
  gem "vcr", "~> 6.2"
  gem "rails-controller-testing", "~> 1.0" # For assigns and assert_template in controller tests
  gem "capybara", "~> 3.39"
  gem "selenium-webdriver", "~> 4.15"
end

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
