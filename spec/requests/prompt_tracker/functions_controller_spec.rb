# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::FunctionsController", type: :request do
  let(:function) { create(:function_definition) }

  describe "GET /functions" do
    it "returns success" do
      get "/prompt_tracker/functions"
      expect(response).to have_http_status(:success)
    end

    it "displays functions" do
      function # create it
      get "/prompt_tracker/functions"
      expect(response.body).to include(function.name)
      expect(response.body).to include(function.description)
    end

    it "searches by name" do
      function # create it
      other_function = create(:function_definition, name: "other_function", description: "Different")

      get "/prompt_tracker/functions", params: { q: function.name }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(function.name)
      expect(response.body).not_to include(other_function.name)
    end

    it "filters by category" do
      function # create it (category: "utility")
      other_function = create(:function_definition, category: "api")

      get "/prompt_tracker/functions", params: { category: "utility" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(function.name)
      expect(response.body).not_to include(other_function.name)
    end

    it "filters by language" do
      function # create it
      get "/prompt_tracker/functions", params: { language: "ruby" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(function.name)
    end

    it "filters by tag" do
      function # create it
      get "/prompt_tracker/functions", params: { tag: function.tags.first }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(function.name)
    end

    it "sorts by name" do
      get "/prompt_tracker/functions", params: { sort: "name" }
      expect(response).to have_http_status(:success)
    end

    it "sorts by most used" do
      get "/prompt_tracker/functions", params: { sort: "most_used" }
      expect(response).to have_http_status(:success)
    end

    it "paginates results" do
      create_list(:function_definition, 25)
      get "/prompt_tracker/functions"
      expect(response).to have_http_status(:success)

      get "/prompt_tracker/functions", params: { page: 2 }
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /functions/:id" do
    it "shows function details" do
      get "/prompt_tracker/functions/#{function.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(function.name)
      expect(response.body).to include(function.description)
      # Code is HTML-escaped in the view
      expect(response.body).to include("def execute(args)")
    end

    it "displays execution history" do
      create(:function_execution, function_definition: function)
      get "/prompt_tracker/functions/#{function.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Execution History")
    end

    it "paginates execution history" do
      create_list(:function_execution, 25, function_definition: function)
      get "/prompt_tracker/functions/#{function.id}"
      expect(response).to have_http_status(:success)

      get "/prompt_tracker/functions/#{function.id}", params: { page: 2 }
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /functions/new" do
    it "shows new function form" do
      get "/prompt_tracker/functions/new"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("New Function")
    end
  end

  describe "POST /functions" do
    let(:valid_params) do
      {
        function_definition: {
          name: "test_function",
          description: "Test function",
          code: "def execute(args)\n  args[:value] * 2\nend",
          language: "ruby",
          category: "utility",
          tags: [ "test", "math" ],
          parameters: {
            "type" => "object",
            "properties" => {
              "value" => { "type" => "integer" }
            },
            "required" => [ "value" ]
          }
        }
      }
    end

    it "creates function" do
      expect {
        post "/prompt_tracker/functions", params: valid_params
      }.to change(PromptTracker::FunctionDefinition, :count).by(1)

      expect(response).to redirect_to("/prompt_tracker/functions/#{PromptTracker::FunctionDefinition.last.id}")
      follow_redirect!
      expect(response.body).to include("Function created successfully")
    end

    it "handles invalid function" do
      expect {
        post "/prompt_tracker/functions", params: {
          function_definition: {
            name: "", # Invalid - blank
            code: "invalid ruby code {{"
          }
        }
      }.not_to change(PromptTracker::FunctionDefinition, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /functions/:id/edit" do
    it "shows edit form" do
      get "/prompt_tracker/functions/#{function.id}/edit"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit Function")
      expect(response.body).to include(function.name)
    end
  end

  describe "PATCH /functions/:id" do
    it "updates function" do
      patch "/prompt_tracker/functions/#{function.id}", params: {
        function_definition: {
          name: "updated_name",
          description: "Updated description"
        }
      }

      expect(response).to redirect_to("/prompt_tracker/functions/#{function.id}")
      follow_redirect!
      expect(response.body).to include("Function updated successfully")

      function.reload
      expect(function.name).to eq("updated_name")
      expect(function.description).to eq("Updated description")
    end

    it "handles invalid update" do
      patch "/prompt_tracker/functions/#{function.id}", params: {
        function_definition: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /functions/:id" do
    it "destroys function" do
      function # create it first

      expect {
        delete "/prompt_tracker/functions/#{function.id}"
      }.to change(PromptTracker::FunctionDefinition, :count).by(-1)

      expect(response).to redirect_to("/prompt_tracker/functions")
      follow_redirect!
      expect(response.body).to include("Function deleted successfully")
    end
  end

  describe "POST /functions/:id/test" do
    let(:deployed_function) { create(:function_definition, :deployed) }

    it "tests function with valid arguments (JSON)" do
      post "/prompt_tracker/functions/#{deployed_function.id}/test",
           params: { arguments: '{"operation": "add", "a": 5, "b": 3}' },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to have_key("success?")
      expect(json).to have_key("result")
    end

    it "handles invalid JSON" do
      post "/prompt_tracker/functions/#{deployed_function.id}/test",
           params: { arguments: "invalid json" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Invalid JSON")
    end

    it "tests function with HTML format" do
      post "/prompt_tracker/functions/#{deployed_function.id}/test",
           params: { arguments: '{"operation": "add", "a": 5, "b": 3}' }

      expect(response).to redirect_to("/prompt_tracker/functions/#{deployed_function.id}")
      follow_redirect!
      expect(response.body).to include("Test executed successfully")
    end

    it "returns error when function is not deployed (JSON)" do
      post "/prompt_tracker/functions/#{function.id}/test",
           params: { arguments: '{"operation": "add", "a": 5, "b": 3}' },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("must be deployed to AWS Lambda")
    end

    it "returns error when function is not deployed (HTML)" do
      post "/prompt_tracker/functions/#{function.id}/test",
           params: { arguments: '{"operation": "add", "a": 5, "b": 3}' }

      expect(response).to redirect_to("/prompt_tracker/functions/#{function.id}")
      follow_redirect!
      expect(response.body).to include("must be deployed to AWS Lambda")
    end
  end
end
