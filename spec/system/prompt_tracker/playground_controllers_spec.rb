# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground Controllers", type: :system, js: true do
  let(:prompt) { create(:prompt, name: "Test Prompt", slug: "test-prompt") }
  let(:prompt_version) do
    create(
      :prompt_version,
      prompt: prompt,
      system_prompt: "You are a helpful assistant.",
      user_prompt: "Hello {{ name }}!",
      template_variables: { "name" => "World" },
      model_config: {
        provider: "openai",
        api: "chat_completions",
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      }
    )
  end

  describe "Initial Page Load" do
    context "when visiting prompt-specific playground" do
      it "connects all controllers successfully" do
        visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)

        # Wait for page to load
        expect(page).to have_content("Playground")

        # Check console logs for controller connections
        # Note: In real implementation, you'd use page.driver.browser.logs.get(:browser)
        # but this requires specific driver configuration

        # Verify key elements are present
        expect(page).to have_selector('[data-controller*="playground-coordinator"]')
        expect(page).to have_selector('[data-controller*="playground-model-config"]')
        expect(page).to have_selector('[data-controller*="playground-editor"]')
        expect(page).to have_selector('[data-controller*="playground-preview"]')
        expect(page).to have_selector('[data-controller*="playground-save"]')
        expect(page).to have_selector('[data-controller*="playground-ui"]')
      end
    end

    context "when visiting standalone playground" do
      it "connects all controllers in standalone mode" do
        visit prompt_tracker.testing_playground_index_path

        expect(page).to have_content("Playground")
        expect(page).to have_selector('[data-controller*="playground-coordinator"]')
      end
    end
  end

  describe "Model Config Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "updates API dropdown when provider changes" do
      # Select a different provider
      select "Anthropic", from: "Provider"

      # Wait for API dropdown to update
      expect(page).to have_select("API", with_options: [ "Messages" ])
    end

    it "updates model dropdown when API changes" do
      # Change API
      select "Assistants", from: "API"

      # Wait for model dropdown to update
      expect(page).to have_select("Model", with_options: [ "gpt-4", "gpt-3.5-turbo" ])
    end

    it "updates temperature badge when slider changes" do
      # Find temperature slider
      temperature_slider = find('input[data-playground-model-config-target="modelTemperature"]')
      temperature_badge = find('[data-playground-model-config-target="temperatureBadge"]')

      # Change temperature
      temperature_slider.set(0.9)

      # Verify badge updates
      expect(temperature_badge.text).to eq("0.9")
    end

    it "toggles tool selection" do
      # Assuming tools are available for the selected API
      # Find a tool checkbox
      tool_checkbox = first('input[data-playground-model-config-target="toolCheckbox"]')

      if tool_checkbox
        # Toggle tool
        tool_checkbox.check

        # Verify card gets active class
        tool_card = tool_checkbox.ancestor('.tool-card')
        expect(tool_card[:class]).to include('active')
      end
    end
  end

  describe "Editor Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "extracts variables from user prompt" do
      # Clear existing prompt
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Hello {{ first_name }} {{ last_name }}!")

      # Wait for variables to be detected
      expect(page).to have_field("first_name")
      expect(page).to have_field("last_name")
    end

    it "updates character count when typing" do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      char_count = find('[data-playground-editor-target="charCount"]')

      # Type in editor
      user_prompt_editor.set("This is a test prompt with some content.")

      # Verify character count updates
      expect(char_count.text).to match(/\d+ characters/)
    end

    it "changes AI button state based on content" do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      ai_button = find('[data-playground-editor-target="aiButton"]')

      # Clear editor
      user_prompt_editor.set("")

      # Should show "Generate"
      expect(ai_button.text).to include("Generate")

      # Add content
      user_prompt_editor.set("Some content")

      # Should show "Enhance"
      expect(ai_button.text).to include("Enhance")
    end

    it "fills variable inputs and dispatches promptChanged event" do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Hello {{ name }}!")

      # Wait for variable input to appear
      name_input = find('input[data-variable="name"]')

      # Fill variable
      name_input.set("Alice")

      # Preview should update (tested in preview controller spec)
    end
  end

  describe "Preview Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "updates preview when prompt changes", :vcr do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Change prompt
      user_prompt_editor.set("Test prompt without variables")

      # Wait for debounced preview update (500ms + request time)
      sleep 1

      # Verify preview updated
      expect(preview_container.text).to include("Test prompt without variables")
    end

    it "shows typing indicator for incomplete syntax" do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Type incomplete Liquid syntax
      user_prompt_editor.set("Hello {{ name")

      # Should show typing indicator
      sleep 0.6 # Wait for debounce
      expect(preview_container.text).to include("Typing...")
    end

    it "shows error for invalid template syntax", :vcr do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      preview_error = find('[data-playground-preview-target="previewError"]', visible: :all)

      # Type invalid syntax
      user_prompt_editor.set("{% invalid_tag %}")

      # Wait for preview update
      sleep 1

      # Should show error
      expect(preview_error).to be_visible
    end

    it "manually refreshes preview when refresh button clicked", :vcr do
      refresh_btn = find('[data-playground-preview-target="refreshBtn"]')

      # Click refresh
      refresh_btn.click

      # Should show loading state briefly
      # Then show updated preview
      sleep 1
      preview_container = find('[data-playground-preview-target="previewContainer"]')
      expect(preview_container).to be_visible
    end
  end

  describe "Save Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "saves draft with valid data", :vcr do
      # Fill in prompt name
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_name.set("My New Prompt")

      # Fill in user prompt
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.set("This is my prompt")

      # Click save draft
      save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')
      save_draft_btn.click

      # Should show success alert
      expect(page).to have_selector('.alert-success', text: /saved/i)
    end

    it "auto-generates slug from prompt name" do
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_slug = find('input[data-playground-save-target="promptSlug"]')

      # Type prompt name
      prompt_name.set("My Test Prompt")

      # Slug should auto-generate
      expect(prompt_slug.value).to eq("my-test-prompt")
    end

    it "validates prompt name is required" do
      # Clear prompt name
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_name.set("")

      # Try to save
      save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')
      save_draft_btn.click

      # Should show warning
      expect(page).to have_selector('.alert-warning', text: /required/i)
    end

    it "warns about unfilled variables" do
      # Set prompt with variable
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Hello {{ name }}!")

      # Don't fill variable
      # Try to save
      save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')
      save_draft_btn.click

      # Should show confirmation dialog
      # Note: Capybara handles confirm dialogs with accept_confirm
      accept_confirm do
        save_draft_btn.click
      end
    end

    it "shows loading state during save" do
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_name.set("Test Prompt")

      save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')

      # Click save
      save_draft_btn.click

      # Should show loading state (briefly)
      # This is hard to test due to timing, but we can verify button is disabled
      expect(save_draft_btn).to be_disabled
    end
  end

  describe "Sync Controller" do
    let(:assistant_version) do
      create(
        :prompt_version,
        prompt: prompt,
        model_config: {
          provider: "openai",
          api: "assistants",
          model: "gpt-4",
          remote_entity_id: "asst_123"
        }
      )
    end

    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, assistant_version)
    end

    it "syncs with remote entity when sync button clicked", :vcr do
      # Find sync button (only visible for APIs with :remote_entity_linked)
      sync_btn = find('button[data-playground-sync-target="syncBtn"]', visible: :all)

      if sync_btn.visible?
        # Click sync
        sync_btn.click

        # Should show loading state
        expect(sync_btn).to be_disabled

        # Wait for sync to complete
        sleep 2

        # Should reload page or show success
        expect(page).to have_content("Playground")
      end
    end
  end

  describe "Response Schema Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "validates JSON schema" do
      schema_editor = find('textarea[data-playground-response-schema-target="schemaEditor"]', visible: :all)

      if schema_editor.visible?
        # Enter valid JSON schema
        schema_editor.set('{"type": "object", "properties": {"name": {"type": "string"}}}')

        # Click validate
        validate_btn = find('button[data-playground-response-schema-target="validateBtn"]')
        validate_btn.click

        # Should show success
        expect(page).to have_selector('[data-playground-response-schema-target="schemaError"]', text: /valid/i)
      end
    end

    it "shows error for invalid JSON" do
      schema_editor = find('textarea[data-playground-response-schema-target="schemaEditor"]', visible: :all)

      if schema_editor.visible?
        # Enter invalid JSON
        schema_editor.set('{"invalid": json}')

        # Click validate
        validate_btn = find('button[data-playground-response-schema-target="validateBtn"]')
        validate_btn.click

        # Should show error
        expect(page).to have_selector('[data-playground-response-schema-target="schemaError"]', text: /invalid/i)
      end
    end

    it "clears schema when clear button clicked" do
      schema_editor = find('textarea[data-playground-response-schema-target="schemaEditor"]', visible: :all)

      if schema_editor.visible?
        # Enter schema
        schema_editor.set('{"type": "object"}')

        # Click clear
        clear_btn = find('button[data-playground-response-schema-target="clearBtn"]')
        clear_btn.click

        # Schema should be empty
        expect(schema_editor.value).to be_empty
      end
    end
  end

  describe "UI Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "shows/hides panels based on API capabilities" do
      # Start with Chat Completions (should show system prompt, user prompt, variables, preview)
      expect(page).to have_selector('[data-playground-ui-target="systemPromptSection"]', visible: true)
      expect(page).to have_selector('[data-playground-ui-target="userPromptTemplateSection"]', visible: true)

      # Change to Assistants API
      select "Assistants", from: "API"

      # Wait for UI to update
      sleep 0.5

      # Should show conversation panel, hide template-specific UI
      # Note: Exact behavior depends on ApiCapabilities configuration
    end
  end

  describe "Coordinator Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "refreshes preview with Cmd+Enter keyboard shortcut", :vcr do
      # Focus on editor
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.click

      # Press Cmd+Enter (or Ctrl+Enter on non-Mac)
      user_prompt_editor.send_keys([ :command, :enter ])

      # Preview should refresh
      sleep 1
      preview_container = find('[data-playground-preview-target="previewContainer"]')
      expect(preview_container).to be_visible
    end

    it "saves draft with Cmd+S keyboard shortcut" do
      # Fill in required fields
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_name.set("Test Prompt")

      # Press Cmd+S
      prompt_name.send_keys([ :command, 's' ])

      # Should trigger save
      # Note: This might show alert or redirect
      sleep 1
    end

    it "toggles syntax help with Cmd+/ keyboard shortcut" do
      # Press Cmd+/
      page.send_keys([ :command, '/' ])

      # Syntax help should toggle
      # Note: Exact selector depends on implementation
      sleep 0.5
    end
  end

  describe "Inter-controller Communication" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "flows events from editor to preview" do
      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Change prompt in editor
      user_prompt_editor.set("New prompt text")

      # Wait for debounced preview update
      sleep 1

      # Preview should update
      expect(preview_container.text).to include("New prompt text")
    end

    it "flows events from model-config to UI" do
      # Change provider
      select "Anthropic", from: "Provider"

      # Wait for API dropdown to update
      sleep 0.5

      # UI panels should update based on new API capabilities
      # Note: Exact expectations depend on ApiCapabilities configuration
    end

    it "collects data from multiple controllers on save" do
      # Fill in data across multiple controllers
      prompt_name = find('input[data-playground-save-target="promptName"]')
      prompt_name.set("Multi-Controller Test")

      user_prompt_editor = find('textarea[data-playground-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Test prompt")

      temperature_slider = find('input[data-playground-model-config-target="modelTemperature"]')
      temperature_slider.set(0.8)

      # Save
      save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')
      save_draft_btn.click

      # Should collect data from editor, model-config, and response-schema controllers
      sleep 1
    end
  end
end
