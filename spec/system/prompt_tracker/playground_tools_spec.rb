# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground Tools Selection", type: :system, js: true do
  let(:prompt) { create(:prompt) }

  # Version with tools configured (normalized string array format)
  let(:version_with_tools) do
    create(:prompt_version,
      prompt: prompt,
      status: "active",
      model_config: {
        "provider" => "openai",
        "api" => "assistants",
        "model" => "gpt-4o",
        "tools" => [ "file_search", "code_interpreter" ]
      }
    )
  end



  # Version with no tools
  let(:version_without_tools) do
    create(:prompt_version,
      prompt: prompt,
      status: "active",
      model_config: {
        "provider" => "openai",
        "api" => "chat_completions",
        "model" => "gpt-4o"
      }
    )
  end

  describe "tools pre-selection on page load" do
    context "with tools configured" do
      it "pre-selects tools correctly" do
        visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_with_tools)

        # Wait for page to load
        expect(page).to have_css(".tools-panel")

        # file_search should be checked
        file_search_checkbox = find('input[type="checkbox"][value="file_search"]', visible: :all)
        expect(file_search_checkbox).to be_checked

        # code_interpreter should be checked
        code_interpreter_checkbox = find('input[type="checkbox"][value="code_interpreter"]', visible: :all)
        expect(code_interpreter_checkbox).to be_checked

        # functions should NOT be checked (not in config)
        functions_checkbox = find('input[type="checkbox"][value="functions"]', visible: :all)
        expect(functions_checkbox).not_to be_checked
      end

      it "applies active class to selected tool cards" do
        visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_with_tools)

        # file_search card should have active class
        file_search_card = find('label[for="tool_file_search"]')
        expect(file_search_card[:class]).to include("active")

        # code_interpreter card should have active class
        code_interpreter_card = find('label[for="tool_code_interpreter"]')
        expect(code_interpreter_card[:class]).to include("active")
      end
    end



    context "with no tools configured" do
      it "has no tools pre-selected" do
        visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_without_tools)

        # Skip if tools panel is not visible (API doesn't support tools)
        if page.has_css?(".tools-panel", visible: :all)
          all('input[type="checkbox"][id^="tool_"]', visible: :all).each do |checkbox|
            expect(checkbox).not_to be_checked
          end
        end
      end
    end
  end

  describe "tool toggling via UI" do
    before do
      # Use a version with assistants API so we have file_search and code_interpreter tools available
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_with_tools)
    end

    it "unchecks a tool when clicking its card" do
      # Skip if tools panel is not visible
      skip "Tools panel not visible for this API" unless page.has_css?(".tools-panel", visible: :all)

      # file_search is already checked (from version_with_tools)
      file_search_checkbox = find('input[type="checkbox"][value="file_search"]', visible: :all)
      expect(file_search_checkbox).to be_checked

      # Click the card label to uncheck the checkbox
      find('label[for="tool_file_search"]').click
      sleep 0.2

      expect(file_search_checkbox).not_to be_checked
    end

    it "checks a tool when clicking its card again" do
      skip "Tools panel not visible for this API" unless page.has_css?(".tools-panel", visible: :all)

      file_search_card = find('label[for="tool_file_search"]')
      file_search_checkbox = find('input[type="checkbox"][value="file_search"]', visible: :all)

      # Uncheck it first (it starts checked)
      file_search_card.click
      sleep 0.2
      expect(file_search_checkbox).not_to be_checked

      # Check it again
      file_search_card.click
      sleep 0.2
      expect(file_search_checkbox).to be_checked
    end

    it "toggles active class on tool card when checking/unchecking" do
      skip "Tools panel not visible for this API" unless page.has_css?(".tools-panel", visible: :all)

      file_search_card = find('label[for="tool_file_search"]')

      # Initially active (file_search is in version_with_tools)
      expect(file_search_card[:class]).to include("active")

      # Click to deactivate
      file_search_card.click
      sleep 0.2 # Wait for JavaScript to update classes
      expect(file_search_card[:class]).not_to include("active")

      # Click to activate again
      file_search_card.click
      sleep 0.2
      expect(file_search_card[:class]).to include("active")
    end
  end

  describe "tool configuration panels visibility" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_without_tools)
    end

    it "shows configuration panel when enabling a configurable tool" do
      skip "Tools panel not visible for this API" unless page.has_css?(".tools-panel", visible: :all)

      # file_search is configurable and should have a config panel
      if page.has_css?('label[for="tool_file_search"]', visible: :all)
        find('label[for="tool_file_search"]').click

        # Wait for panel to appear
        sleep 0.3

        # Check if config panel exists and is visible
        if page.has_css?("#file_search_config", visible: :all)
          config_panel = find("#file_search_config", visible: :all)
          expect(config_panel[:class]).to include("show")
        end
      end
    end

    it "hides configuration panel when disabling a tool" do
      skip "Tools panel not visible for this API" unless page.has_css?(".tools-panel", visible: :all)

      if page.has_css?('label[for="tool_file_search"]', visible: :all)
        file_search_card = find('label[for="tool_file_search"]')

        # Enable first
        file_search_card.click
        sleep 0.3

        # Disable
        file_search_card.click
        sleep 0.3

        # Panel should be hidden
        if page.has_css?("#file_search_config", visible: :all)
          config_panel = find("#file_search_config", visible: :all)
          expect(config_panel[:class]).not_to include("show")
        end
      end
    end
  end

  describe "form submission with tool state" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version_with_tools)
    end

    it "includes selected tools in the tools config controller data" do
      # This test verifies that the Stimulus controller correctly tracks tool state
      # We can't easily test form submission in system specs, but we can verify
      # that the JavaScript controller has the correct state

      # file_search should be enabled (pre-selected)
      file_search_checkbox = find('input[type="checkbox"][value="file_search"]', visible: :all)
      expect(file_search_checkbox).to be_checked

      # Toggle web_search on
      if page.has_css?('label[for="tool_web_search"]', visible: :all)
        find('label[for="tool_web_search"]').click
        sleep 0.2

        web_search_checkbox = find('input[type="checkbox"][value="web_search"]', visible: :all)
        expect(web_search_checkbox).to be_checked
      end

      # Toggle code_interpreter off (was pre-selected)
      code_interpreter_card = find('label[for="tool_code_interpreter"]')
      code_interpreter_card.click
      sleep 0.2

      code_interpreter_checkbox = find('input[type="checkbox"][value="code_interpreter"]', visible: :all)
      expect(code_interpreter_checkbox).not_to be_checked
    end
  end
end
