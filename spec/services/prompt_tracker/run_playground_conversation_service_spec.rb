# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::RunPlaygroundConversationService do
  describe ".call" do
    let(:content) { "Hello, how are you?" }
    let(:system_prompt) { "You are a helpful assistant." }
    let(:user_prompt_template) { nil }
    let(:model_config) { { provider: "openai", api: "responses", model: "gpt-4o", temperature: 0.7 } }
    let(:conversation_state) { { messages: [], previous_response_id: nil, started_at: nil } }
    let(:variables) { {} }

    let(:mock_response) do
      {
        text: "I'm doing well, thank you!",
        response_id: "resp_123",
        usage: { prompt_tokens: 10, completion_tokens: 20 },
        tool_calls: []
      }
    end

    before do
      allow(PromptTracker::OpenaiResponseService).to receive(:call).and_return(mock_response)
      allow(PromptTracker::OpenaiResponseService).to receive(:call_with_context).and_return(mock_response)
    end

    context "with valid input" do
      it "returns a successful result" do
        result = described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(result.success?).to be true
        expect(result.content).to eq("I'm doing well, thank you!")
        expect(result.error).to be_nil
      end

      it "uses ConversationStateBuilder for state management" do
        result = described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(result.conversation_state[:messages].size).to eq(2)
        expect(result.conversation_state[:messages].first[:role]).to eq("user")
        expect(result.conversation_state[:messages].last[:role]).to eq("assistant")
        expect(result.conversation_state[:previous_response_id]).to eq("resp_123")
      end

      it "passes instructions separately for first message" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(PromptTracker::OpenaiResponseService).to have_received(:call).with(
          model: "gpt-4o",
          input: content,
          instructions: system_prompt,
          tools: [],
          tool_config: nil,
          temperature: 0.7
        )
      end
    end

    context "with existing conversation (follow-up turn)" do
      let(:conversation_state) do
        {
          messages: [
            { role: "user", content: "Hi" },
            { role: "assistant", content: "Hello!" }
          ],
          previous_response_id: "resp_previous",
          started_at: Time.current.iso8601
        }
      end

      it "calls OpenaiResponseService.call_with_context" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(PromptTracker::OpenaiResponseService).to have_received(:call_with_context).with(
          model: "gpt-4o",
          input: content,
          previous_response_id: "resp_previous",
          tools: [],
          tool_config: nil,
          temperature: 0.7
        )
      end

      it "appends new messages to existing conversation" do
        result = described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(result.conversation_state[:messages].size).to eq(4)
      end
    end

    context "validation errors" do
      it "returns error when content is blank" do
        result = described_class.call(
          content: "",
          system_prompt: system_prompt,
          model_config: model_config
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Message content is required")
      end

      it "returns error when provider is missing" do
        result = described_class.call(
          content: content,
          model_config: { api: "responses", model: "gpt-4o" }
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Provider is required")
      end

      it "returns error when api is missing" do
        result = described_class.call(
          content: content,
          model_config: { provider: "openai", model: "gpt-4o" }
        )

        expect(result.success?).to be false
        expect(result.error).to eq("API is required")
      end
    end

    context "with tools enabled" do
      let(:model_config) do
        { provider: "openai", api: "responses", model: "gpt-4o", tools: %w[web_search code_interpreter] }
      end

      it "passes tools to the service" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state
        )

        expect(PromptTracker::OpenaiResponseService).to have_received(:call).with(
          hash_including(tools: [ :web_search, :code_interpreter ])
        )
      end
    end
  end
end
