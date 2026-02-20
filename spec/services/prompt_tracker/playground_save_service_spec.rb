# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe PlaygroundSaveService do
    let(:valid_params) do
      {
        user_prompt: "Hello {{name}}",
        system_prompt: "You are a helpful assistant",
        notes: "Test notes",
        model_config: { "provider" => "openai", "model" => "gpt-4o" },
        response_schema: nil
      }
    end

    describe ".call" do
      it "delegates to instance call" do
        service = instance_double(described_class)
        allow(described_class).to receive(:new).and_return(service)
        allow(service).to receive(:call)

        described_class.call(params: valid_params)

        expect(service).to have_received(:call)
      end
    end

    describe "#call" do
      context "when creating a new prompt (standalone mode)" do
        let(:params) { valid_params.merge(prompt_name: "My New Prompt", prompt_slug: "my_new_prompt") }

        it "creates a new prompt with a version" do
          result = described_class.call(params: params)

          expect(result.success?).to be true
          expect(result.action).to eq(:created)
          expect(result.prompt).to be_persisted
          expect(result.prompt.name).to eq("My New Prompt")
          expect(result.prompt.slug).to eq("my_new_prompt")
          expect(result.version).to be_persisted
          expect(result.version.user_prompt).to eq("Hello {{name}}")
          expect(result.version.status).to eq("draft")
          expect(result.errors).to be_empty
        end

        it "auto-generates slug when not provided" do
          params_without_slug = valid_params.merge(prompt_name: "My New Prompt", prompt_slug: nil)

          result = described_class.call(params: params_without_slug)

          expect(result.success?).to be true
          expect(result.prompt.slug).to eq("my_new_prompt")
        end

        it "sets description from notes" do
          result = described_class.call(params: params)

          expect(result.prompt.description).to eq("Test notes")
        end

        it "fails when prompt_name is blank" do
          params_without_name = valid_params.merge(prompt_name: nil)

          result = described_class.call(params: params_without_name)

          expect(result.success?).to be false
          expect(result.errors).to include("Prompt name is required")
          expect(result.prompt).to be_nil
          expect(result.version).to be_nil
        end

        it "fails when user_prompt is blank" do
          params_without_prompt = valid_params.merge(prompt_name: "Test", user_prompt: nil)

          result = described_class.call(params: params_without_prompt)

          expect(result.success?).to be false
          expect(result.errors).to include("User prompt can't be blank")
        end
      end

      context "when creating a new version for existing prompt" do
        let!(:prompt) { Prompt.create!(name: "Existing Prompt", slug: "existing_prompt") }
        let!(:existing_version) do
          prompt.prompt_versions.create!(
            user_prompt: "Old prompt",
            version_number: 1,
            status: "active"
          )
        end

        it "creates a new draft version" do
          result = described_class.call(params: valid_params, prompt: prompt)

          expect(result.success?).to be true
          expect(result.action).to eq(:created)
          expect(result.version).to be_persisted
          expect(result.version.version_number).to eq(2)
          expect(result.version.status).to eq("draft")
          expect(result.version.user_prompt).to eq("Hello {{name}}")
        end

        it "preserves the existing prompt" do
          result = described_class.call(params: valid_params, prompt: prompt)

          expect(result.prompt).to eq(prompt)
          expect(prompt.prompt_versions.count).to eq(2)
        end

        it "saves model_config" do
          result = described_class.call(params: valid_params, prompt: prompt)

          expect(result.version.model_config).to eq({ "provider" => "openai", "model" => "gpt-4o" })
        end

        it "creates new version even when save_action is update but version has responses" do
          existing_version.llm_responses.create!(
            rendered_prompt: "Test",
            response_text: "Response",
            model: "gpt-4",
            provider: "openai",
            status: "success"
          )
          params_with_update = valid_params.merge(save_action: "update")

          result = described_class.call(
            params: params_with_update,
            prompt: prompt,
            prompt_version: existing_version
          )

          expect(result.success?).to be true
          expect(result.action).to eq(:created)
          expect(result.version.id).not_to eq(existing_version.id)
          expect(result.version_created_reason).to eq(:production_immutable)
        end

        it "creates new version with structural_change reason when tests exist and structural fields change" do
          existing_version.tests.create!(name: "Test case")
          params_with_structural_change = valid_params.merge(
            save_action: "update",
            model_config: { "provider" => "anthropic", "model" => "claude-3" }
          )

          result = described_class.call(
            params: params_with_structural_change,
            prompt: prompt,
            prompt_version: existing_version
          )

          expect(result.success?).to be true
          expect(result.action).to eq(:created)
          expect(result.version.id).not_to eq(existing_version.id)
          expect(result.version_created_reason).to eq(:structural_change_with_tests)
        end

        it "updates existing version when tests exist but only content fields change" do
          # Create version with a user_prompt that has a variable so we have a proper variables_schema
          existing_version.update!(
            user_prompt: "Hello {{name}}",
            model_config: { "provider" => "openai", "model" => "gpt-4o" }
          )
          existing_version.reload # Clear dirty tracking and let variables_schema be extracted
          existing_version.tests.create!(name: "Test case")

          # Capture the exact values before modifying
          current_variables_schema = existing_version.variables_schema
          current_response_schema = existing_version.response_schema
          current_model_config = existing_version.model_config

          # Change only the text content, keeping the same variable
          params_content_change = valid_params.merge(
            save_action: "update",
            user_prompt: "Greetings {{name}}, how are you?", # Different text, same variable
            model_config: current_model_config, # Same as existing
            variables_schema: current_variables_schema, # Preserve existing
            response_schema: current_response_schema # Preserve existing
          )

          result = described_class.call(
            params: params_content_change,
            prompt: prompt,
            prompt_version: existing_version
          )

          expect(result.success?).to be true
          expect(result.action).to eq(:updated)
          expect(result.version.id).to eq(existing_version.id)
          expect(result.version_created_reason).to be_nil
        end

        it "creates new version when save_action is new_version" do
          params_with_new_version = valid_params.merge(save_action: "new_version")

          result = described_class.call(
            params: params_with_new_version,
            prompt: prompt,
            prompt_version: existing_version
          )

          expect(result.success?).to be true
          expect(result.action).to eq(:created)
          expect(result.version.id).not_to eq(existing_version.id)
        end
      end

      context "when updating an existing version" do
        let!(:prompt) { Prompt.create!(name: "Existing Prompt", slug: "existing_prompt") }
        let!(:draft_version) do
          prompt.prompt_versions.create!(
            user_prompt: "Old prompt",
            version_number: 1,
            status: "draft"
          )
        end
        let(:update_params) { valid_params.merge(save_action: "update") }

        it "updates the existing version when it has no responses" do
          result = described_class.call(
            params: update_params,
            prompt: prompt,
            prompt_version: draft_version
          )

          expect(result.success?).to be true
          expect(result.action).to eq(:updated)
          expect(result.version.id).to eq(draft_version.id)

          draft_version.reload
          expect(draft_version.user_prompt).to eq("Hello {{name}}")
          expect(draft_version.system_prompt).to eq("You are a helpful assistant")
        end

        it "preserves version_number when updating" do
          result = described_class.call(
            params: update_params,
            prompt: prompt,
            prompt_version: draft_version
          )

          expect(result.version.version_number).to eq(1)
        end

        it "updates notes" do
          result = described_class.call(
            params: update_params,
            prompt: prompt,
            prompt_version: draft_version
          )

          expect(result.version.notes).to eq("Test notes")
        end
      end

      context "with response_schema" do
        let!(:prompt) { Prompt.create!(name: "Schema Prompt", slug: "schema_prompt") }
        let(:response_schema) do
          {
            "type" => "object",
            "properties" => {
              "sentiment" => { "type" => "string" }
            },
            "required" => [ "sentiment" ]
          }
        end
        let(:params_with_schema) do
          valid_params.merge(prompt_name: "Test", response_schema: response_schema)
        end

        it "saves response_schema when creating new prompt" do
          result = described_class.call(params: params_with_schema)

          expect(result.success?).to be true
          expect(result.version.response_schema).to eq(response_schema)
        end

        it "saves response_schema when creating new version" do
          result = described_class.call(
            params: valid_params.merge(response_schema: response_schema),
            prompt: prompt
          )

          expect(result.version.response_schema).to eq(response_schema)
        end

        it "clears response_schema when nil is passed" do
          version = prompt.prompt_versions.create!(
            user_prompt: "Test",
            version_number: 1,
            status: "draft",
            response_schema: response_schema
          )
          params_clear_schema = valid_params.merge(save_action: "update", response_schema: nil)

          result = described_class.call(
            params: params_clear_schema,
            prompt: prompt,
            prompt_version: version
          )

          expect(result.success?).to be true
          version.reload
          expect(version.response_schema).to be_nil
        end
      end
    end

    describe "Result object" do
      it "has the expected attributes including version_created_reason" do
        result = described_class::Result.new(
          success?: true,
          action: :created,
          prompt: nil,
          version: nil,
          errors: [],
          version_created_reason: :production_immutable
        )

        expect(result).to respond_to(:success?)
        expect(result).to respond_to(:action)
        expect(result).to respond_to(:prompt)
        expect(result).to respond_to(:version)
        expect(result).to respond_to(:errors)
        expect(result).to respond_to(:version_created_reason)
        expect(result.version_created_reason).to eq(:production_immutable)
      end

      it "allows nil version_created_reason" do
        result = described_class::Result.new(
          success?: true,
          action: :updated,
          prompt: nil,
          version: nil,
          errors: [],
          version_created_reason: nil
        )

        expect(result.version_created_reason).to be_nil
      end
    end
  end
end
