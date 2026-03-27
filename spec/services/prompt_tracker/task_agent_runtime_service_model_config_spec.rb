# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskAgentRuntimeService, type: :service do
  describe "model_config access with string keys" do
    let(:prompt) { create(:prompt) }
    let(:prompt_version) do
      create(:prompt_version,
        prompt: prompt,
        model_config: {
          "provider" => "openai",
          "api" => "chat_completions",
          "model" => "gpt-5-pro",
          "temperature" => 0.7,
          "max_tokens" => 1000,
          "tools" => [ "functions" ],
          "tool_config" => {
            "functions" => []
          }
        }
      )
    end
    let(:deployed_agent) do
      create(:deployed_agent,
        prompt_version: prompt_version
      )
    end
    let(:task_run) { create(:task_run, deployed_agent: deployed_agent) }
    let(:service) { described_class.new(task_agent: deployed_agent, task_run: task_run) }

    it "correctly extracts model from model_config with string keys" do
      # Mock the LLM service to verify it receives the correct model
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_call_original

      # Stub the actual LLM call to avoid making real API requests
      allow_any_instance_of(PromptTracker::LlmClients::RubyLlmService).to receive(:call).and_return({
        text: "Test response",
        model: "gpt-5-pro",
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
        tool_calls: []
      })

      messages = [ { role: "user", content: "Test message" } ]
      service.send(:call_llm, messages)

      # Verify that RubyLlmService was initialized with the correct model
      expect(PromptTracker::LlmClients::RubyLlmService).to have_received(:new).with(
        hash_including(
          model: "gpt-5-pro",
          temperature: 0.7
        )
      )
    end

    it "does not pass nil model when model_config uses string keys" do
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_call_original
      allow_any_instance_of(PromptTracker::LlmClients::RubyLlmService).to receive(:call).and_return({
        text: "Test response",
        model: "gpt-5-pro",
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
        tool_calls: []
      })

      messages = [ { role: "user", content: "Test message" } ]
      service.send(:call_llm, messages)

      # Verify that model is NOT nil
      expect(PromptTracker::LlmClients::RubyLlmService).to have_received(:new) do |args|
        expect(args[:model]).not_to be_nil
        expect(args[:model]).to eq("gpt-5-pro")
      end
    end

    it "correctly extracts provider from model_config with string keys" do
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_call_original
      allow_any_instance_of(PromptTracker::LlmClients::RubyLlmService).to receive(:call).and_return({
        text: "Test response",
        model: "gpt-5-pro",
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
        tool_calls: []
      })

      messages = [ { role: "user", content: "Test message" } ]
      service.send(:call_llm, messages)

      # Trigger track_llm_response to verify provider extraction
      llm_response = {
        text: "Test",
        model: "gpt-5-pro",
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
        tool_calls: []
      }

      service.instance_variable_set(:@conversation_history, [ { role: "user", content: "Test" } ])
      response_record = service.send(:track_llm_response, llm_response)

      expect(response_record.provider).to eq("openai")
      expect(response_record.provider).not_to be_nil
    end
  end
end
