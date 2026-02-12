# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground Generate Feature", type: :system, js: true do
  let(:prompt) { PromptTracker::Prompt.create!(name: "test_prompt", description: "Test") }
  let(:prompt_version) do
    prompt.prompt_versions.create!(
      system_prompt: "",
      user_prompt: "placeholder",  # Will be cleared in the UI
      status: "draft"
    )
  end

  before do
    # Mock the PromptGeneratorService to avoid actual LLM calls
    allow(PromptTracker::PromptGeneratorService).to receive(:generate).and_return(
      {
        system_prompt: "You are a helpful customer support assistant.",
        user_prompt: "Help {{ customer_name }} with their {{ issue }}.",
        variables: [ "customer_name", "issue" ],
        explanation: "This prompt is designed for customer support interactions."
      }
    )
  end

  describe "Generate button visibility" do
    it "shows Generate button when prompts are empty" do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)

      # Clear the prompts in the UI
      page.execute_script("document.getElementById('system-prompt-editor').value = ''")
      page.execute_script("document.getElementById('user-prompt-editor').value = ''")
      page.execute_script("document.getElementById('system-prompt-editor').dispatchEvent(new Event('input', { bubbles: true }))")

      expect(page).to have_button("Generate", visible: :visible)
    end
  end

  describe "Generate modal interaction" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)

      # Clear the prompts in the UI to show Generate button
      page.execute_script("document.getElementById('system-prompt-editor').value = ''")
      page.execute_script("document.getElementById('user-prompt-editor').value = ''")
      page.execute_script("document.getElementById('system-prompt-editor').dispatchEvent(new Event('input', { bubbles: true }))")
    end

    it "opens modal when Generate button is clicked" do
      click_button "Generate"

      expect(page).to have_css("#generatePromptModal.show", visible: :visible)
      expect(page).to have_text("Generate New Prompt")
      expect(page).to have_field("generateDescription")
    end

    it "shows validation warning when description is empty" do
      click_button "Generate"

      within "#generatePromptModal" do
        click_button "Generate Prompt"
      end

      expect(page).to have_text("Please describe what your prompt should do")
    end
  end

  describe "Prompt generation flow" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)

      # Clear the prompts in the UI to show Generate button
      page.execute_script("document.getElementById('system-prompt-editor').value = ''")
      page.execute_script("document.getElementById('user-prompt-editor').value = ''")
      page.execute_script("document.getElementById('system-prompt-editor').dispatchEvent(new Event('input', { bubbles: true }))")
    end

    it "generates prompts from description successfully" do
      # Click Generate button
      click_button "Generate"

      # Fill in description
      within "#generatePromptModal" do
        fill_in "generateDescription", with: "A customer support chatbot for handling billing issues"
        click_button "Generate Prompt"
      end

      # Should show generating modal
      expect(page).to have_css("#generatingModal.show", visible: :visible, wait: 1)

      # Wait for success message (indicates generation completed)
      expect(page).to have_text("This prompt is designed for customer support interactions.", wait: 15)

      # Check that prompts were populated
      system_prompt_value = page.evaluate_script(
        'document.getElementById("system-prompt-editor").value'
      )
      user_prompt_value = page.evaluate_script(
        'document.getElementById("user-prompt-editor").value'
      )

      expect(system_prompt_value).to eq("You are a helpful customer support assistant.")
      expect(user_prompt_value).to eq("Help {{ customer_name }} with their {{ issue }}.")

      # Check that variables were detected and inputs created
      # Variable inputs have id="var-{name}" and data-variable="{name}"
      # Note: The variables section may be hidden based on API capabilities,
      # so we check for existence regardless of visibility
      expect(page).to have_css('input[data-variable="customer_name"]', visible: :all)
      expect(page).to have_css('input[data-variable="issue"]', visible: :all)
    end

    it "handles generation errors gracefully" do
      # Mock an error response
      allow(PromptTracker::PromptGeneratorService).to receive(:generate).and_raise(StandardError.new("API Error"))

      click_button "Generate"

      within "#generatePromptModal" do
        fill_in "generateDescription", with: "Test description"
        click_button "Generate Prompt"
      end

      # Should show error message
      expect(page).to have_text("Generation failed", wait: 10)
    end
  end
end
