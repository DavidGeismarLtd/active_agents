# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe LlmCallService do
    let(:prompt) do
      Prompt.create!(
        name: "Test Prompt",
        slug: "test_prompt",
        description: "A test prompt"
      )
    end

    let(:version_with_config) do
      prompt.prompt_versions.create!(
        user_prompt: "Hello {{name}}",
        version_number: 1,
        status: "active",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true }
        ],
        model_config: {
          "provider" => "openai",
          "model" => "gpt-4",
          "temperature" => 0.7
        }
      )
    end

    let(:version_without_config) do
      prompt.prompt_versions.create!(
        user_prompt: "Hello {{name}}",
        version_number: 2,
        status: "draft",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true }
        ],
        model_config: {}
      )
    end

    describe ".track" do
      context "with provider/model from model_config" do
        before { version_with_config }  # Ensure version is created

        it "tracks LLM call using version's model_config" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "Alice" }
          ) do |rendered_prompt|
            expect(rendered_prompt).to eq("Hello Alice")
            "Hello Alice! How can I help?"
          end

          expect(result[:response_text]).to eq("Hello Alice! How can I help?")
          expect(result[:llm_response]).to be_a(LlmResponse)
          expect(result[:llm_response].provider).to eq("openai")
          expect(result[:llm_response].model).to eq("gpt-4")
          expect(result[:llm_response].status).to eq("success")
        end

        it "accepts string response" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "Bob" }
          ) { |_| "Simple response" }

          expect(result[:response_text]).to eq("Simple response")
        end

        it "accepts hash response with token counts" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "Charlie" }
          ) do |_|
            {
              text: "Hello Charlie!",
              tokens_prompt: 10,
              tokens_completion: 5,
              metadata: { model: "gpt-4" }
            }
          end

          expect(result[:response_text]).to eq("Hello Charlie!")
          expect(result[:llm_response].tokens_prompt).to eq(10)
          expect(result[:llm_response].tokens_completion).to eq(5)
          expect(result[:llm_response].tokens_total).to eq(15)
        end
      end

      context "with provider/model override" do
        before { version_with_config }  # Ensure version is created

        it "uses override instead of model_config" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "Diana" },
            provider: "anthropic",
            model: "claude-3-opus"
          ) { |_| "Hello Diana!" }

          expect(result[:llm_response].provider).to eq("anthropic")
          expect(result[:llm_response].model).to eq("claude-3-opus")
        end
      end

      context "without model_config and without override" do
        before { version_with_config.update!(status: "draft") }
        before { version_without_config.update!(status: "active") }

        it "raises error if provider/model not specified" do
          expect {
            described_class.track(
              prompt_slug: "test_prompt",
              variables: { name: "Eve" }
            ) { |_| "Hello!" }
          }.to raise_error(ArgumentError, /Provider and model must be specified/)
        end

        it "works if provider/model explicitly provided" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "Frank" },
            provider: "openai",
            model: "gpt-3.5-turbo"
          ) { |_| "Hello Frank!" }

          expect(result[:llm_response].provider).to eq("openai")
          expect(result[:llm_response].model).to eq("gpt-3.5-turbo")
        end
      end

      context "error handling" do
        before { version_with_config }  # Ensure version is created for valid tests

        it "raises error if prompt not found" do
          expect {
            described_class.track(
              prompt_slug: "nonexistent",
              variables: {}
            ) { |_| "Response" }
          }.to raise_error(LlmCallService::PromptNotFoundError)
        end

        it "raises error if no block given" do
          expect {
            described_class.track(
              prompt_slug: "test_prompt",
              variables: {}
            )
          }.to raise_error(LlmCallService::NoBlockGivenError)
        end

        it "raises error if block returns invalid format" do
          expect {
            described_class.track(
              prompt_slug: "test_prompt",
              variables: { name: "Test" }
            ) { |_| 123 }  # Invalid - not string or hash
          }.to raise_error(LlmResponseContract::InvalidResponseError)
        end

        it "raises error if block returns hash without text" do
          expect {
            described_class.track(
              prompt_slug: "test_prompt",
              variables: { name: "Test" }
            ) { |_| { tokens_prompt: 10 } }  # Missing :text
          }.to raise_error(LlmResponseContract::InvalidResponseError)
        end
      end

      context "with user context and metadata" do
        before { version_with_config }  # Ensure version is created

        it "stores user context" do
          result = described_class.track(
            prompt_slug: "test_prompt",
            variables: { name: "George" },
            user_id: "user_123",
            session_id: "session_abc",
            environment: "production",
            metadata: { ip: "192.168.1.1" }
          ) { |_| "Hello George!" }

          expect(result[:llm_response].user_id).to eq("user_123")
          expect(result[:llm_response].session_id).to eq("session_abc")
          expect(result[:llm_response].environment).to eq("production")
          expect(result[:llm_response].context).to eq({ "ip" => "192.168.1.1" })
        end
      end

      context "with specific version" do
        it "uses specified version instead of active" do
          version_with_config.update!(status: "deprecated")
          version_without_config.update!(status: "active", model_config: { "provider" => "anthropic", "model" => "claude-3" })

          result = described_class.track(
            prompt_slug: "test_prompt",
            version: 1,  # Use version 1 (deprecated)
            variables: { name: "Helen" }
          ) { |_| "Hello Helen!" }

          expect(result[:llm_response].prompt_version).to eq(version_with_config)
          expect(result[:llm_response].provider).to eq("openai")  # From version 1's config
        end
      end
    end
  end
end
