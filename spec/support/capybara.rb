# frozen_string_literal: true

require "capybara/rails"
require "capybara/rspec"
require "selenium/webdriver"

# Configure Capybara
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_chrome_headless

# Configure Selenium Chrome headless
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1400,1400")

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Set default wait time for asynchronous processes
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  # Use :rack_test by default (faster, no JS)
  # Use js: true metadata to enable JavaScript driver
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium_chrome_headless
  end
end
