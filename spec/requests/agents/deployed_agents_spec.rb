# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agents API", type: :request do
  let(:prompt_version) { create(:prompt_version, :active) }
  let(:deployed_agent) do
    create(:deployed_agent,
           prompt_version: prompt_version,
           status: "active",
           deployment_config: {
             auth: { type: "api_key" },
             rate_limit: { requests_per_minute: 60 },
             conversation_ttl: 3600,
             cors: { allowed_origins: [ "https://example.com" ] }
           })
  end
  let(:api_key) { deployed_agent.instance_variable_get(:@plain_api_key) }

  before do
    # Ensure API key is generated
    deployed_agent.send(:generate_api_key)
    @plain_api_key = deployed_agent.instance_variable_get(:@plain_api_key)
  end

  describe "POST /agents/:slug/chat" do
    let(:valid_params) do
      {
        message: "Hello, how are you?",
        conversation_id: "conv_123",
        metadata: { user_id: "user_456" }
      }
    end

    context "with valid authentication" do
      let(:headers) do
        {
          "Authorization" => "Bearer #{@plain_api_key}",
          "Content-Type" => "application/json"
        }
      end

      it "returns a successful response" do
        # Mock the AgentRuntimeService
        allow(PromptTracker::AgentRuntimeService).to receive(:call).and_return(
          PromptTracker::AgentRuntimeService::Result.new(
            success?: true,
            response: "I'm doing well, thank you!",
            conversation_id: "conv_123",
            function_calls: []
          )
        )

        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["response"]).to eq("I'm doing well, thank you!")
        expect(json["conversation_id"]).to eq("conv_123")
        expect(json["function_calls"]).to eq([])
      end

      it "calls AgentRuntimeService with correct parameters" do
        expect(PromptTracker::AgentRuntimeService).to receive(:call).with(
          deployed_agent: deployed_agent,
          message: "Hello, how are you?",
          conversation_id: "conv_123",
          metadata: { "user_id" => "user_456" }
        ).and_return(
          PromptTracker::AgentRuntimeService::Result.new(
            success?: true,
            response: "Response",
            conversation_id: "conv_123",
            function_calls: []
          )
        )

        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: headers
      end

      it "generates a new conversation_id if not provided" do
        allow(PromptTracker::AgentRuntimeService).to receive(:call) do |args|
          expect(args[:conversation_id]).to be_nil
          PromptTracker::AgentRuntimeService::Result.new(
            success?: true,
            response: "Response",
            conversation_id: "generated_conv_id",
            function_calls: []
          )
        end

        post "/agents/#{deployed_agent.slug}/chat",
             params: { message: "Hello" }.to_json,
             headers: headers

        json = JSON.parse(response.body)
        expect(json["conversation_id"]).to eq("generated_conv_id")
      end
    end

    context "with authentication type 'none'" do
      before do
        deployed_agent.update!(
          deployment_config: deployed_agent.deployment_config.merge(
            auth: { type: "none" }
          )
        )
      end

      it "allows requests without API key" do
        allow(PromptTracker::AgentRuntimeService).to receive(:call).and_return(
          PromptTracker::AgentRuntimeService::Result.new(
            success?: true,
            response: "Response",
            conversation_id: "conv_123",
            function_calls: []
          )
        )

        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)
      end
    end

    context "without authentication" do
      it "returns 401 unauthorized" do
        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid API key" do
      it "returns 401 unauthorized" do
        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: {
               "Authorization" => "Bearer invalid_key",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with paused agent" do
      before { deployed_agent.pause! }

      it "returns 503 service unavailable" do
        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: {
               "Authorization" => "Bearer #{@plain_api_key}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:service_unavailable)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Agent is paused")
      end
    end

    context "with agent in error state" do
      before { deployed_agent.update!(status: "error", error_message: "Something went wrong") }

      it "returns 503 service unavailable" do
        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: {
               "Authorization" => "Bearer #{@plain_api_key}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:service_unavailable)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Agent is experiencing errors")
      end
    end

    context "with non-existent agent" do
      it "returns 404 not found" do
        post "/agents/non-existent-slug/chat",
             params: valid_params.to_json,
             headers: {
               "Authorization" => "Bearer #{@plain_api_key}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Agent not found")
      end
    end

    context "when AgentRuntimeService returns error" do
      it "returns 422 unprocessable entity" do
        allow(PromptTracker::AgentRuntimeService).to receive(:call).and_return(
          PromptTracker::AgentRuntimeService::Result.new(
            success?: false,
            error: "Message is required"
          )
        )

        post "/agents/#{deployed_agent.slug}/chat",
             params: valid_params.to_json,
             headers: {
               "Authorization" => "Bearer #{@plain_api_key}",
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Message is required")
      end
    end
  end

  describe "GET /agents/:slug/info" do
    let(:headers) do
      {
        "Authorization" => "Bearer #{@plain_api_key}"
      }
    end

    before do
      # Create some function definitions
      create(:function_definition, name: "get_weather", description: "Get weather for a city")
      deployed_agent.function_definitions << PromptTracker::FunctionDefinition.last
    end

    it "returns agent information" do
      get "/agents/#{deployed_agent.slug}/info", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq(deployed_agent.name)
      expect(json["slug"]).to eq(deployed_agent.slug)
      expect(json["status"]).to eq("active")
      expect(json["functions"]).to be_an(Array)
      expect(json["functions"].first["name"]).to eq("get_weather")
    end

    context "with authentication type 'none'" do
      before do
        deployed_agent.update!(
          deployment_config: deployed_agent.deployment_config.merge(
            auth: { type: "none" }
          )
        )
      end

      it "allows requests without API key" do
        get "/agents/#{deployed_agent.slug}/info"

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "CORS support" do
    let(:headers) do
      {
        "Authorization" => "Bearer #{@plain_api_key}",
        "Content-Type" => "application/json",
        "Origin" => "https://example.com"
      }
    end

    it "sets CORS headers for allowed origin" do
      allow(PromptTracker::AgentRuntimeService).to receive(:call).and_return(
        PromptTracker::AgentRuntimeService::Result.new(
          success?: true,
          response: "Response",
          conversation_id: "conv_123",
          function_calls: []
        )
      )

      post "/agents/#{deployed_agent.slug}/chat",
           params: { message: "Hello" }.to_json,
           headers: headers

      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://example.com")
      expect(response.headers["Access-Control-Allow-Methods"]).to be_present
      expect(response.headers["Access-Control-Allow-Headers"]).to be_present
    end

    it "does not set CORS headers for disallowed origin" do
      headers["Origin"] = "https://evil.com"

      allow(PromptTracker::AgentRuntimeService).to receive(:call).and_return(
        PromptTracker::AgentRuntimeService::Result.new(
          success?: true,
          response: "Response",
          conversation_id: "conv_123",
          function_calls: []
        )
      )

      post "/agents/#{deployed_agent.slug}/chat",
           params: { message: "Hello" }.to_json,
           headers: headers

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end
end
