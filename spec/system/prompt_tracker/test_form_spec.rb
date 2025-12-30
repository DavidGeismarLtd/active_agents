# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Test Form", type: :system, js: true do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt, status: "active") }

  describe "evaluator configuration with JavaScript" do
    before do
      visit "/prompt_tracker/testing/prompts/#{prompt.id}/versions/#{version.id}"
      click_button "New Test"
      # Wait for modal to appear
      expect(page).to have_css("#new-test-modal", visible: true)
    end

    context "on page load" do
      it "disables required fields for unchecked evaluators" do
        # Find an unchecked evaluator checkbox
        exact_match_checkbox = find('input[type="checkbox"][data-evaluator-key="exact_match"]', visible: :all)
        expect(exact_match_checkbox).not_to be_checked

        # The config section should be collapsed
        config_section = find("#config_exact_match", visible: :all)
        expect(config_section[:class]).to include("collapse")

        # Required fields should be disabled
        within config_section do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to eq("true")
        end
      end

      it "enables required fields for checked evaluators" do
        # Check if any evaluator is pre-selected (shouldn't be by default)
        # If length evaluator is checked by default, its fields should be enabled
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]', visible: :all)

        if length_checkbox.checked?
          config_section = find("#config_length", visible: :all)
          within config_section do
            min_length_field = find('input[name="config[min_length]"]', visible: :all)
            expect(min_length_field[:disabled]).to be_nil
          end
        end
      end
    end

    context "when checking an evaluator" do
      it "expands the config section and enables required fields" do
        # Find and check the exact_match evaluator
        exact_match_checkbox = find('input[type="checkbox"][data-evaluator-key="exact_match"]')
        exact_match_checkbox.check

        # Wait for the config section to expand
        config_section = find("#config_exact_match")
        expect(config_section[:class]).not_to include("collapse")

        # Required fields should now be enabled (disabled attribute should be false or nil)
        within config_section do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to be_in([ nil, "false", false ])
        end
      end

      it "updates the hidden evaluator_configs JSON field" do
        # Check the length evaluator
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]')
        length_checkbox.check

        # Fill in the config fields
        within "#config_length" do
          fill_in "config[min_length]", with: 50
          fill_in "config[max_length]", with: 200
        end

        # Give JavaScript time to update the hidden field
        sleep 0.5

        # Check the hidden field value
        hidden_field = find('#evaluator_configs_json', visible: false)
        configs = JSON.parse(hidden_field.value)

        expect(configs).to be_an(Array)
        expect(configs.length).to eq(1)
        expect(configs.first["evaluator_key"]).to eq("length")
        expect(configs.first["config"]["min_length"]).to eq(50)
        expect(configs.first["config"]["max_length"]).to eq(200)
      end
    end

    context "when unchecking an evaluator" do
      it "collapses the config section and disables required fields" do
        # First check the evaluator
        exact_match_checkbox = find('input[type="checkbox"][data-evaluator-key="exact_match"]')
        exact_match_checkbox.check

        # Wait for expansion
        config_section = find("#config_exact_match")
        expect(config_section[:class]).not_to include("collapse")

        # Now uncheck it
        exact_match_checkbox.uncheck

        # Config section should collapse
        expect(config_section[:class]).to include("collapse")

        # Required fields should be disabled
        within config_section do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to eq("true")
        end
      end

      it "removes the evaluator from the hidden JSON field" do
        # Check the length evaluator
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]')
        length_checkbox.check

        # Fill in config
        within "#config_length" do
          fill_in "config[min_length]", with: 50
        end

        sleep 0.5

        # Verify it's in the JSON
        hidden_field = find('#evaluator_configs_json', visible: false)
        configs = JSON.parse(hidden_field.value)
        expect(configs.length).to eq(1)

        # Now uncheck it
        length_checkbox.uncheck
        sleep 0.5

        # Verify it's removed from the JSON
        configs = JSON.parse(hidden_field.value)
        expect(configs.length).to eq(0)
      end
    end

    context "with multiple evaluators" do
      it "manages multiple evaluators independently" do
        # Check multiple evaluators
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]')
        keyword_checkbox = find('input[type="checkbox"][data-evaluator-key="keyword"]')

        length_checkbox.check
        keyword_checkbox.check

        # Fill in configs for both
        within "#config_length" do
          fill_in "config[min_length]", with: 10
          fill_in "config[max_length]", with: 100
        end

        within "#config_keyword" do
          fill_in "config[required_keywords]", with: "hello\nworld"
        end

        sleep 0.5

        # Check the hidden field has both
        hidden_field = find('#evaluator_configs_json', visible: false)
        configs = JSON.parse(hidden_field.value)

        expect(configs.length).to eq(2)
        expect(configs.map { |c| c["evaluator_key"] }).to contain_exactly("length", "keyword")
      end

      it "keeps other evaluators enabled when one is unchecked" do
        # Check two evaluators
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]')
        keyword_checkbox = find('input[type="checkbox"][data-evaluator-key="keyword"]')

        length_checkbox.check
        keyword_checkbox.check

        # Uncheck one
        length_checkbox.uncheck

        # Length fields should be disabled
        length_config = find("#config_length", visible: :all)
        within length_config do
          min_length_field = find('input[name="config[min_length]"]', visible: :all)
          expect(min_length_field[:disabled]).to eq("true")
        end

        # Keyword fields should still be enabled
        keyword_config = find("#config_keyword", visible: :all)
        within keyword_config do
          required_keywords_field = find('textarea[name="config[required_keywords]"]', visible: :all)
          expect(required_keywords_field[:disabled]).to be_in([ nil, "false", false ])
        end
      end
    end

    context "preventing HTML5 validation errors" do
      it "allows form submission when only selected evaluators are filled" do
        # This test verifies that disabled required fields don't block form submission
        # We don't actually submit the form (that's tested in request specs)
        # We just verify that the required fields are properly disabled

        # Select and configure length evaluator
        length_checkbox = find('input[type="checkbox"][data-evaluator-key="length"]')
        length_checkbox.check

        within "#config_length" do
          fill_in "config[min_length]", with: 10
          fill_in "config[max_length]", with: 100
        end

        # Verify that other evaluators' required fields are disabled
        exact_match_config = find("#config_exact_match", visible: :all)
        within exact_match_config do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to eq("true")
        end

        llm_judge_config = find("#config_llm_judge", visible: :all)
        within llm_judge_config do
          judge_model_field = find('select[name="config[judge_model]"]', visible: :all)
          expect(judge_model_field[:disabled]).to eq("true")
        end

        # The form should be submittable (no HTML5 validation errors)
        # We can't actually test form submission without filling all required fields
        # (name, template_variables, model_config), but we've verified that
        # the evaluator required fields won't block submission
      end

      it "re-enables required fields when evaluator is selected" do
        # Start with exact_match unchecked (required fields disabled)
        exact_match_config = find("#config_exact_match", visible: :all)
        within exact_match_config do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to eq("true")
        end

        # Check the evaluator
        exact_match_checkbox = find('input[type="checkbox"][data-evaluator-key="exact_match"]')
        exact_match_checkbox.check

        # Required fields should now be enabled
        within exact_match_config do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to be_in([ nil, "false", false ])
        end

        # Fill in the field
        within exact_match_config do
          fill_in "config[expected_text]", with: "Expected response"
        end

        # Uncheck the evaluator again
        exact_match_checkbox.uncheck

        # Required field should be disabled again
        within exact_match_config do
          expected_text_field = find('textarea[name="config[expected_text]"]', visible: :all)
          expect(expected_text_field[:disabled]).to eq("true")
        end
      end
    end
  end
end
