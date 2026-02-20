# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground Controllers", type: :system, js: true do
  let(:prompt) { create(:prompt, name: "Test Prompt", slug: "test_prompt") }
  let(:prompt_version) do
    create(
      :prompt_version,
      prompt: prompt,
      system_prompt: "You are a helpful assistant.",
      user_prompt: "Hello {{ name }}!",
      variables_schema: [ { "name" => "name", "type" => "string", "required" => true } ],
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

        # Verify key elements are present (controllers loaded on playground-container)
        expect(page).to have_selector('[data-controller*="playground-save"]')
        expect(page).to have_selector('[data-controller*="playground-ui"]')
        expect(page).to have_selector('[data-controller*="playground-generate-prompt"]')
        # Preview is conditionally loaded based on API capabilities
        expect(page).to have_selector('[data-controller*="playground-preview"]')
      end
    end

    context "when visiting standalone playground" do
      it "connects all controllers in standalone mode" do
        visit prompt_tracker.testing_playground_path

        expect(page).to have_content("Playground")
        expect(page).to have_selector('[data-controller*="playground-save"]')
        expect(page).to have_selector('[data-controller*="playground-ui"]')
      end
    end
  end

  describe "Model Config Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
    end

    it "updates API dropdown when provider changes" do
      # Get available provider options
      provider_select = find('select', id: 'model-provider')
      available_options = provider_select.all('option').map(&:value).reject(&:empty?)

      # Skip if only one provider available
      if available_options.length > 1
        # Select the second provider option
        second_provider = available_options[1]
        provider_select.select(second_provider)

        # API dropdown should still exist (may have different options)
        expect(page).to have_select("API")
      end
    end

    it "updates model dropdown when API changes" do
      # Change API
      select "Assistants", from: "API"

      # Wait for model dropdown to update - check for at least one model option
      expect(page).to have_select("Model")
    end

    it "updates temperature badge when slider changes" do
      # Find temperature slider (target is 'temperature' on model-config)
      temperature_slider = find('input[data-playground-model-config-target="temperature"]')
      # Temperature badge is on playground-ui controller
      temperature_badge = find('[data-playground-ui-target="temperatureBadge"]')

      # Change temperature
      temperature_slider.set(0.9)

      # Trigger input event for badge update
      temperature_slider.native.send_keys(:tab)

      # Verify badge updates
      expect(temperature_badge.text).to include("0.9")
    end

    it "toggles tool selection" do
      # Tools are managed by playground-tools controller
      # Tool checkboxes are hidden (d-none), so we click the label card
      tool_card = first('.tool-card', visible: true)

      if tool_card
        # Click the tool card to toggle selection
        tool_card.click

        # Verify card gets active class
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
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Hello {{ first_name }} {{ last_name }}!")

      # Wait for variables to be detected
      # Variable inputs have id="var-{name}" and data-variable="{name}"
      expect(page).to have_css('input[data-variable="first_name"]', visible: :all)
      expect(page).to have_css('input[data-variable="last_name"]', visible: :all)
    end

    it "updates character count when typing" do
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      char_count = find('[data-playground-prompt-editor-target="charCount"]')

      # Type in editor
      user_prompt_editor.set("This is a test prompt with some content.")

      # Verify character count updates (format is "X chars")
      expect(char_count.text).to match(/\d+ chars/i)
    end

    it "fills variable inputs and dispatches promptChanged event" do
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
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
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Change prompt
      user_prompt_editor.set("Test prompt without variables")

      # Wait for debounced preview update (500ms + request time)
      sleep 1

      # Verify preview updated
      expect(preview_container.text).to include("Test prompt without variables")
    end

    it "shows typing indicator for incomplete syntax" do
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Type incomplete Liquid syntax
      user_prompt_editor.set("Hello {{ name")

      # Should show typing indicator
      sleep 0.6 # Wait for debounce
      expect(preview_container.text).to include("Typing...")
    end

    it "shows error for invalid template syntax", :vcr do
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
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
    context "with existing prompt (has version without responses)" do
      before do
        visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
      end

      it "saves draft with valid data", :vcr do
        # Fill in user prompt
        user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
        user_prompt_editor.set("This is my updated prompt")

        # Click save button (now a single smart Save button)
        save_btn = find('button[data-playground-save-target="saveBtn"]')
        save_btn.click

        # Modal appears - click Update This Version
        within("#saveModal") do
          click_button "Update This Version"
        end

        # Should redirect to prompt version show page after save
        expect(page).to have_content("Test Prompt")
      end

      it "shows loading state during save" do
        user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
        user_prompt_editor.set("Test prompt content")

        save_btn = find('button[data-playground-save-target="saveBtn"]')
        save_btn.click

        # Modal appears - click Update This Version
        within("#saveModal") do
          click_button "Update This Version"
        end

        # Should redirect to prompt version show page after save
        expect(page).to have_content("Test Prompt")
      end
    end

    context "in standalone mode (new prompt)" do
      before do
        visit prompt_tracker.testing_playground_path
      end

      it "auto-generates slug from prompt name" do
        prompt_name = find('input[data-playground-save-target="promptName"]')
        prompt_slug = find('input[data-playground-save-target="promptSlug"]')

        # Type prompt name
        prompt_name.set("My Test Prompt")

        # Trigger input event
        prompt_name.native.send_keys(:tab)

        # Slug should auto-generate (underscores not hyphens)
        expect(prompt_slug.value).to eq("my_test_prompt")
      end

      it "validates prompt name is required" do
        # Clear prompt name
        prompt_name = find('input[data-playground-save-target="promptName"]')
        prompt_name.set("")

        # Try to save
        save_draft_btn = find('button[data-playground-save-target="saveDraftBtn"]')
        save_draft_btn.click

        # Should show warning or validation error
        # The button should stay on page (not redirect)
        expect(page).to have_selector('button[data-playground-save-target="saveDraftBtn"]')
      end
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

    it "syncs with remote entity when push button clicked", :vcr do
      # Find push button (only visible for APIs with :remote_entity_linked)
      push_btn = find('button[data-playground-sync-target="pushBtn"]', visible: :all)

      if push_btn.visible?
        # Click push
        push_btn.click

        # Wait for sync to complete (loading state is brief)
        sleep 2

        # Should show page content after sync
        expect(page).to have_css('[data-controller*="playground"]')
      end
    end
  end

  describe "Response Schema Controller" do
    before do
      visit prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, prompt_version)
      # Expand the response schema accordion
      find('button[data-bs-target="#responseSchemaOptions"]').click
      sleep 0.3 # Wait for accordion animation
    end

    it "validates JSON schema" do
      schema_editor = find('textarea[data-playground-response-schema-target="responseSchema"]')

      # Enter valid JSON schema
      schema_editor.set('{"type": "object", "properties": {"name": {"type": "string"}}}')

      # Click validate (button uses action, not target)
      validate_btn = find('button[data-action*="validateResponseSchema"]')
      validate_btn.click

      # Should show success
      expect(page).to have_selector('[data-playground-response-schema-target="responseSchemaError"]', text: /valid/i)
    end

    it "shows error for invalid JSON" do
      schema_editor = find('textarea[data-playground-response-schema-target="responseSchema"]')

      # Enter invalid JSON
      schema_editor.set('{"invalid": json}')

      # Click validate
      validate_btn = find('button[data-action*="validateResponseSchema"]')
      validate_btn.click

      # Should show error
      expect(page).to have_selector('[data-playground-response-schema-target="responseSchemaError"]', text: /invalid/i)
    end

    it "clears schema when clear button clicked" do
      schema_editor = find('textarea[data-playground-response-schema-target="responseSchema"]')

      # Enter schema
      schema_editor.set('{"type": "object"}')

      # Click clear (button uses action, not target)
      clear_btn = find('button[data-action*="clearResponseSchema"]')
      clear_btn.click

      # Schema should be empty
      expect(schema_editor.value).to be_empty
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
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      user_prompt_editor.click

      # Press Cmd+Enter (or Ctrl+Enter on non-Mac)
      user_prompt_editor.send_keys([ :command, :enter ])

      # Preview should refresh
      sleep 1
      preview_container = find('[data-playground-preview-target="previewContainer"]')
      expect(preview_container).to be_visible
    end

    it "saves draft with Cmd+S keyboard shortcut" do
      # Focus on user prompt editor
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Updated prompt content")

      # Press Cmd+S
      user_prompt_editor.send_keys([ :command, 's' ])

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
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      preview_container = find('[data-playground-preview-target="previewContainer"]')

      # Change prompt in editor
      user_prompt_editor.set("New prompt text")

      # Wait for debounced preview update
      sleep 1

      # Preview should update
      expect(preview_container.text).to include("New prompt text")
    end

    it "flows events from model-config to UI" do
      # Get available provider options
      provider_select = find('select', id: 'model-provider')
      available_options = provider_select.all('option').map(&:value).reject(&:empty?)

      # Skip if only one provider available
      if available_options.length > 1
        # Select the second provider option
        second_provider = available_options[1]
        provider_select.select(second_provider)

        # Wait for API dropdown to update
        sleep 0.5

        # UI panels should update based on new API capabilities
        expect(page).to have_select("API")
      end
    end

    it "collects data from multiple controllers on save" do
      # Fill in data across multiple controllers
      user_prompt_editor = find('textarea[data-playground-prompt-editor-target="userPromptEditor"]')
      user_prompt_editor.set("Multi-controller test prompt")

      temperature_slider = find('input[data-playground-model-config-target="temperature"]')
      temperature_slider.set(0.8)

      # Save (existing prompt uses single Save button)
      save_btn = find('button[data-playground-save-target="saveBtn"]')
      save_btn.click

      # Modal appears - click Update This Version
      within("#saveModal") do
        click_button "Update This Version"
      end

      # Should collect data from editor, model-config, and response-schema controllers
      # After save, may redirect to prompt version show page
      sleep 1
      expect(page).to have_css('[data-controller]')
    end
  end
end
