# System Specs Implementation Summary

## ✅ What Was Implemented

Comprehensive system specs for the PromptTest form's evaluator configuration JavaScript behavior.

### Files Created/Modified

1. **`Gemfile`** - Added Capybara and Selenium WebDriver gems
2. **`spec/support/capybara.rb`** - Capybara configuration for headless Chrome
3. **`spec/system/prompt_tracker/prompt_test_form_spec.rb`** - System specs (10 tests)
4. **`spec/system/prompt_tracker/README.md`** - Documentation for running and debugging
5. **`spec/system/prompt_tracker/SYSTEM_SPECS_SUMMARY.md`** - This file

### Test Coverage

The system specs test the JavaScript behavior managed by `evaluator_configs_controller.js`:

#### 1. **On Page Load** (2 tests)
- ✅ Disables required fields for unchecked evaluators
- ✅ Enables required fields for checked evaluators (if any are pre-selected)

#### 2. **When Checking an Evaluator** (2 tests)
- ✅ Expands the config section and enables required fields
- ✅ Updates the hidden `evaluator_configs` JSON field with config data

#### 3. **When Unchecking an Evaluator** (2 tests)
- ✅ Collapses the config section and disables required fields
- ✅ Removes the evaluator from the hidden JSON field

#### 4. **With Multiple Evaluators** (2 tests)
- ✅ Manages multiple evaluators independently
- ✅ Keeps other evaluators enabled when one is unchecked

#### 5. **Preventing HTML5 Validation Errors** (2 tests)
- ✅ Verifies disabled required fields don't block form submission
- ✅ Re-enables required fields when evaluator is selected

## 🎯 Key Behaviors Tested

### The Core Problem Solved
Before the JavaScript fix, HTML5 validation would block form submission because:
- Evaluator form partials had `required` fields
- Even unchecked evaluators' forms were in the DOM (just hidden)
- HTML5 validation checks ALL required fields, even hidden ones

### The Solution Tested
The system specs verify that the Stimulus controller:
1. **On page load**: Disables required fields for unchecked evaluators
2. **On check**: Enables required fields and expands config section
3. **On uncheck**: Disables required fields and collapses config section
4. **Updates JSON**: Syncs evaluator configs to hidden field for form submission

## 📊 Test Results

```
10 examples, 0 failures
Finished in 15.11 seconds
```

All tests passing! ✅

## 🚀 Running the Specs

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

## 🔍 What's NOT Tested Here

These system specs focus on **JavaScript behavior only**. They do NOT test:

- ❌ Full form submission (tested in request specs)
- ❌ Server-side validation (tested in request specs)
- ❌ Database persistence (tested in request specs)
- ❌ Model validations (tested in model specs)

This is intentional! System specs are slower than request specs, so we:
- Use **system specs** for JavaScript-dependent behavior
- Use **request specs** for server-side logic and full form submission

## 🛠️ Technical Details

### Dependencies Added
- `capybara` (~> 3.39) - Browser automation
- `selenium-webdriver` (~> 4.15) - Chrome driver

### Configuration
- **Driver**: Headless Chrome (configured in `spec/support/capybara.rb`)
- **Wait time**: 5 seconds (configurable in `spec/support/capybara.rb`)
- **JavaScript**: Enabled with `js: true` metadata

### Key Capybara Methods Used
- `find()` - Find elements by CSS selector
- `fill_in()` - Fill in form fields
- `check()` / `uncheck()` - Toggle checkboxes
- `within()` - Scope actions to a specific element
- `visible: :all` - Find hidden elements

## 📝 Notes

1. **Test Isolation**: Each test is independent and doesn't rely on previous tests
2. **Database Cleaning**: DatabaseCleaner ensures clean state between tests
3. **Random Order**: Tests run in random order to catch dependencies
4. **Screenshots**: Capybara saves screenshots on failure for debugging

## 🎓 Learning Resources

- [Capybara Documentation](https://github.com/teamcapybara/capybara)
- [RSpec System Specs](https://relishapp.com/rspec/rspec-rails/docs/system-specs)
- [Selenium WebDriver](https://www.selenium.dev/documentation/webdriver/)

## 🤝 Complementary Tests

These system specs work together with:
- **Request specs** (`spec/requests/prompt_tracker/prompt_tests_controller_spec.rb`) - Test server-side form submission
- **Model specs** - Test PromptTest and EvaluatorConfig models
- **Controller specs** - Test controller logic

Together, they provide comprehensive coverage of the form functionality!

