# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::PlaygroundExecuteService do
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
          conversation_state: conversation_state,
          variables: variables
        )

        expect(result.success?).to be true
        expect(result.content).to eq("I'm doing well, thank you!")
        expect(result.error).to be_nil
      end

      it "returns conversation state with messages" do
        result = described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state,
          variables: variables
        )

        expect(result.conversation_state[:messages].size).to eq(2)
        expect(result.conversation_state[:messages].first[:role]).to eq("user")
        expect(result.conversation_state[:messages].last[:role]).to eq("assistant")
        expect(result.conversation_state[:previous_response_id]).to eq("resp_123")
      end

      it "calls OpenaiResponseService.call with system_prompt as instructions for first message" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          model_config: model_config,
          conversation_state: conversation_state,
          variables: variables
        )

        # system_prompt becomes the instructions when no user_prompt_template is provided
        expect(PromptTracker::OpenaiResponseService).to have_received(:call).with(
          model: "gpt-4o",
          user_prompt: content,
          system_prompt: system_prompt,
          tools: [],
          tool_config: nil,
          temperature: 0.7
        )
      end
    end

    context "with user_prompt_template" do
      let(:user_prompt_template) { "Please respond to: {{message}}" }
      let(:variables) { { message: "test input" } }

      it "combines system_prompt and rendered user_prompt_template into instructions" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          user_prompt_template: user_prompt_template,
          model_config: model_config,
          conversation_state: conversation_state,
          variables: variables
        )

        expected_instructions = "You are a helpful assistant.\n\nPlease respond to: test input"
        expect(PromptTracker::OpenaiResponseService).to have_received(:call).with(
          model: "gpt-4o",
          user_prompt: content,
          system_prompt: expected_instructions,
          tools: [],
          tool_config: nil,
          temperature: 0.7
        )
      end
    end

    context "with only user_prompt_template (no system_prompt)" do
      let(:system_prompt) { nil }
      let(:user_prompt_template) { "Analyze this: {{topic}}" }
      let(:variables) { { topic: "Ruby on Rails" } }

      it "uses rendered user_prompt_template as instructions" do
        described_class.call(
          content: content,
          system_prompt: system_prompt,
          user_prompt_template: user_prompt_template,
          model_config: model_config,
          conversation_state: conversation_state,
          variables: variables
        )

        expect(PromptTracker::OpenaiResponseService).to have_received(:call).with(
          model: "gpt-4o",
          user_prompt: content,
          system_prompt: "Analyze this: Ruby on Rails",
          tools: [],
          tool_config: nil,
          temperature: 0.7
        )
      end
    end

    context "with existing conversation" do
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
          conversation_state: conversation_state,
          variables: variables
        )

        expect(PromptTracker::OpenaiResponseService).to have_received(:call_with_context).with(
          model: "gpt-4o",
          user_prompt: content,
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
          conversation_state: conversation_state,
          variables: variables
        )

        expect(result.conversation_state[:messages].size).to eq(4)
      end
    end

    context "with blank content" do
      it "returns an error result" do
        result = described_class.call(
          content: "",
          system_prompt: system_prompt,
          model_config: model_config
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Message content is required")
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
