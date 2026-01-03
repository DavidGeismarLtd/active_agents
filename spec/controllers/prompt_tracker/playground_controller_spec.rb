# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    RSpec.describe PlaygroundController, type: :controller do
      routes { PromptTracker::Engine.routes }

      let!(:prompt) { create(:prompt) }
      let!(:version) { create(:prompt_version, prompt: prompt, user_prompt: "Hello {{name}}!", status: "active") }

    describe "GET #show" do
      it "renders the playground page" do
        get :show, params: { prompt_id: prompt.id }

        expect(response).to have_http_status(:success)
        expect(assigns(:prompt)).to eq(prompt)
        expect(assigns(:version)).to eq(version)
      end

      it "extracts variables from template" do
        get :show, params: { prompt_id: prompt.id }

        expect(assigns(:variables)).to include("name")
      end

      it "builds sample variables hash" do
        get :show, params: { prompt_id: prompt.id }

        expect(assigns(:sample_variables)).to be_a(Hash)
        expect(assigns(:sample_variables)).to have_key("name")
      end
    end

    describe "POST #preview" do
      it "renders template successfully" do
        post :preview, params: {
          prompt_id: prompt.id,
          user_prompt: "Hello {{name}}!",
          variables: { name: "John" }
        }, format: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["rendered_user"]).to eq("Hello John!")
        expect(json["engine"]).to eq("mustache")
      end

      it "detects Liquid templates" do
        post :preview, params: {
          prompt_id: prompt.id,
          user_prompt: "Hello {{ name | upcase }}!",
          variables: { name: "john" }
        }, format: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["rendered_user"]).to eq("Hello JOHN!")
        expect(json["engine"]).to eq("liquid")
      end

      it "returns errors for invalid templates" do
        post :preview, params: {
          prompt_id: prompt.id,
          user_prompt: "{% if %}",
          variables: {}
        }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["errors"]).to be_present
      end

      it "extracts variables from template" do
        post :preview, params: {
          prompt_id: prompt.id,
          user_prompt: "Hello {{name}}, welcome to {{place}}!",
          variables: { name: "Alice", place: "Wonderland" }
        }, format: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["variables_detected"]).to include("name", "place")
      end
    end

    describe "POST #save" do
      it "creates a new draft version" do
        expect {
          post :save, params: {
            prompt_id: prompt.id,
            user_prompt: "New template {{var}}",
            notes: "Test draft",
            save_action: "new_version"
          }, format: :json
        }.to change(PromptVersion, :count).by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["version_id"]).to be_present
        expect(json["action"]).to eq("created")

        new_version = PromptVersion.find(json["version_id"])
        expect(new_version.user_prompt).to eq("New template {{var}}")
        expect(new_version.status).to eq("draft")
        expect(new_version.notes).to eq("Test draft")
      end

      it "updates existing version when save_action is 'update' and version has no responses" do
        draft_version = create(:prompt_version, prompt: prompt, status: "draft", user_prompt: "Old template")

        expect {
          post :save, params: {
            prompt_id: prompt.id,
            prompt_version_id: draft_version.id,
            user_prompt: "Updated template {{var}}",
            notes: "Updated notes",
            save_action: "update"
          }, format: :json
        }.not_to change(PromptVersion, :count)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["version_id"]).to eq(draft_version.id)
        expect(json["action"]).to eq("updated")

        draft_version.reload
        expect(draft_version.user_prompt).to eq("Updated template {{var}}")
        expect(draft_version.notes).to eq("Updated notes")
      end

      it "creates new version when save_action is 'update' but version has responses" do
        version_with_responses = create(:prompt_version, prompt: prompt, status: "active")
        create(:llm_response, prompt_version: version_with_responses)

        expect {
          post :save, params: {
            prompt_id: prompt.id,
            prompt_version_id: version_with_responses.id,
            user_prompt: "New template {{var}}",
            notes: "Should create new version",
            save_action: "update"
          }, format: :json
        }.to change(PromptVersion, :count).by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["action"]).to eq("created")

        # Original version should be unchanged
        version_with_responses.reload
        expect(version_with_responses.user_prompt).not_to eq("New template {{var}}")
      end

      it "creates new version when save_action is 'new_version' even if version has no responses" do
        draft_version = create(:prompt_version, prompt: prompt, status: "draft")

        expect {
          post :save, params: {
            prompt_id: prompt.id,
            prompt_version_id: draft_version.id,
            user_prompt: "New template {{var}}",
            notes: "Force new version",
            save_action: "new_version"
          }, format: :json
        }.to change(PromptVersion, :count).by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["action"]).to eq("created")
      end

      it "returns errors for invalid template" do
        post :save, params: {
          prompt_id: prompt.id,
          user_prompt: "",
          notes: "Empty template"
        }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["errors"]).to be_present
      end

      context "with response_schema" do
        let(:valid_response_schema) do
          {
            "type" => "object",
            "properties" => {
              "sentiment" => { "type" => "string", "enum" => %w[positive negative neutral] },
              "confidence" => { "type" => "number" }
            },
            "required" => %w[sentiment confidence]
          }
        end

        it "saves response_schema when creating a new version" do
          expect {
            post :save, params: {
              prompt_id: prompt.id,
              user_prompt: "Analyze: {{text}}",
              notes: "With structured output",
              save_action: "new_version",
              response_schema: valid_response_schema
            }, format: :json
          }.to change(PromptVersion, :count).by(1)

          expect(response).to have_http_status(:success)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true

          new_version = PromptVersion.find(json["version_id"])
          expect(new_version.response_schema).to eq(valid_response_schema)
          expect(new_version.has_response_schema?).to be true
        end

        it "saves response_schema when updating an existing version" do
          draft_version = create(:prompt_version, prompt: prompt, status: "draft", user_prompt: "Old template")

          post :save, params: {
            prompt_id: prompt.id,
            prompt_version_id: draft_version.id,
            user_prompt: "Analyze: {{text}}",
            notes: "Added structured output",
            save_action: "update",
            response_schema: valid_response_schema
          }, format: :json

          expect(response).to have_http_status(:success)
          json = JSON.parse(response.body)
          expect(json["success"]).to be true
          expect(json["action"]).to eq("updated")

          draft_version.reload
          expect(draft_version.response_schema).to eq(valid_response_schema)
        end

        it "clears response_schema when empty is passed" do
          version_with_schema = create(:prompt_version,
            prompt: prompt,
            status: "draft",
            user_prompt: "Old template",
            response_schema: valid_response_schema
          )

          post :save, params: {
            prompt_id: prompt.id,
            prompt_version_id: version_with_schema.id,
            user_prompt: "Updated template",
            notes: "Removed structured output",
            save_action: "update",
            response_schema: nil
          }, format: :json

          expect(response).to have_http_status(:success)

          version_with_schema.reload
          expect(version_with_schema.response_schema).to be_blank
          expect(version_with_schema.has_response_schema?).to be false
        end

        it "returns validation errors for invalid response_schema structure" do
          invalid_schema = { "invalid" => "schema" } # Missing 'type' property

          post :save, params: {
            prompt_id: prompt.id,
            user_prompt: "Template {{var}}",
            notes: "Invalid schema",
            save_action: "new_version",
            response_schema: invalid_schema
          }, format: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json["success"]).to be false
          expect(json["errors"].join).to include("Response schema")
        end
      end
    end

    describe "private methods" do
      let(:controller_instance) { described_class.new }

      describe "#extract_variables_from_template" do
        it "extracts Mustache variables" do
          template = "{{name}} {{age}}"
          variables = controller_instance.send(:extract_variables_from_template, template)

          expect(variables).to match_array([ "name", "age" ])
        end

        it "extracts Liquid filter variables" do
          template = "{{ name | upcase }}"
          variables = controller_instance.send(:extract_variables_from_template, template)

          expect(variables).to include("name")
        end

        it "extracts Liquid conditional variables" do
          template = "{% if premium %}Yes{% endif %}"
          variables = controller_instance.send(:extract_variables_from_template, template)

          expect(variables).to include("premium")
        end

        it "extracts Liquid loop variables" do
          template = "{% for item in items %}{{ item }}{% endfor %}"
          variables = controller_instance.send(:extract_variables_from_template, template)

          expect(variables).to include("items")
        end
      end
    end
  end
  end
end
