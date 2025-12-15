# System Specs for PromptTracker

This directory contains system specs that test the full user experience with JavaScript enabled.

## What These Specs Test

### `prompt_test_form_spec.rb`

Tests the JavaScript behavior of the PromptTest form, specifically the evaluator configuration section managed by the `evaluator_configs_controller.js` Stimulus controller.

**Key behaviors tested:**

1. **On Page Load**
   - Unchecked evaluators have their required fields disabled
   - Config sections for unchecked evaluators are collapsed

2. **Checking an Evaluator**
   - Expands the config section
   - Enables all required fields
   - Updates the hidden `evaluator_configs` JSON field

3. **Unchecking an Evaluator**
   - Collapses the config section
   - Disables all required fields (prevents HTML5 validation errors)
   - Removes the evaluator from the hidden JSON field

4. **Multiple Evaluators**
   - Manages multiple evaluators independently
   - Keeps other evaluators enabled when one is unchecked

5. **Form Submission**
   - Successfully submits with only selected evaluators
   - Successfully submits with multiple evaluators
   - Successfully submits without any evaluators

## Running System Specs

### Run all system specs:
```bash
bundle exec rspec spec/system
```

### Run only the prompt test form specs:
```bash
bundle exec rspec spec/system/prompt_tracker/prompt_test_form_spec.rb
```

### Run with documentation format:
```bash
bundle exec rspec spec/system/prompt_tracker/prompt_test_form_spec.rb --format documentation
```

### Run a specific test:
```bash
bundle exec rspec spec/system/prompt_tracker/prompt_test_form_spec.rb:14
```

## Requirements

System specs require:
- **Capybara** - For browser automation
- **Selenium WebDriver** - For driving Chrome
- **Chrome browser** - Installed on your system

These are already configured in:
- `Gemfile` (gems)
- `spec/support/capybara.rb` (configuration)

## Debugging System Specs

### See what's happening in the browser:
Change the driver from headless to visible Chrome:

```ruby
# In spec/system/prompt_tracker/prompt_test_form_spec.rb
before do
  driven_by :selenium_chrome # instead of :selenium_chrome_headless
  visit "/prompt_tracker/prompts/#{prompt.id}/versions/#{version.id}/tests/new"
end
```

### Add debugging breakpoints:
```ruby
it "does something" do
  # ... test code ...
  
  binding.pry # Pause here to inspect
  
  # ... more test code ...
end
```

### Take screenshots:
```ruby
it "does something" do
  # ... test code ...
  
  save_screenshot("debug.png")
  
  # ... more test code ...
end
```

### Print page HTML:
```ruby
it "does something" do
  puts page.html # Print entire page HTML
end
```

## CI/CD Integration

System specs can be slower than request specs, so you may want to:

1. **Run them separately in CI:**
   ```bash
   # Fast tests
   bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb"
   
   # System tests
   bundle exec rspec spec/system
   ```

2. **Use parallel execution:**
   ```bash
   bundle exec parallel_rspec spec/system
   ```

3. **Configure headless mode for CI** (already configured in `spec/support/capybara.rb`)

## Troubleshooting

### Chrome driver issues:
If you get errors about Chrome driver, make sure Chrome is installed:
```bash
# macOS
brew install --cask google-chrome

# Or update Chrome if already installed
```

### Timeout errors:
Increase the wait time in `spec/support/capybara.rb`:
```ruby
Capybara.default_max_wait_time = 10 # Increase from 5 to 10 seconds
```

### JavaScript not loading:
Make sure your Rails server is properly configured to serve JavaScript assets in test mode.

