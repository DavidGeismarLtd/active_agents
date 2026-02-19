# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe PlaygroundHelper, type: :helper do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    before do
      # Set up instance variable that views would have
      @version = version

      # Set up configuration with new structure
      PromptTracker.configuration.contexts = {
        playground: {
          description: "Prompt testing",
          default_provider: :openai,
          default_api: :chat_completions,
          default_model: "gpt-4o"
        }
      }

      # Make ApplicationHelper methods available to the helper being tested
      # In real views, all helpers are automatically included
      helper.extend(ApplicationHelper)
    end

    describe "#available_tools_for_provider" do
      context "with OpenAI chat_completions" do
        it "returns functions tool" do
          tools = helper.available_tools_for_provider(provider: :openai, api: :chat_completions)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end

      context "with OpenAI responses" do
        it "returns all tools" do
          tools = helper.available_tools_for_provider(provider: :openai, api: :responses)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(4)

          tool_ids = tools.map { |t| t[:id] }
          expect(tool_ids).to contain_exactly("web_search", "file_search", "code_interpreter", "functions")
        end
      end

      context "with OpenAI assistants" do
        it "returns builtin tools and functions" do
          tools = helper.available_tools_for_provider(provider: :openai, api: :assistants)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(3)

          tool_ids = tools.map { |t| t[:id] }
          expect(tool_ids).to contain_exactly("code_interpreter", "file_search", "functions")
        end
      end

      context "with Anthropic messages" do
        it "returns functions tool" do
          tools = helper.available_tools_for_provider(provider: :anthropic, api: :messages)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end

      context "when provider and api are not specified" do
        before do
          @version.update!(
            model_config: {
              provider: "openai",
              api: "responses",
              model: "gpt-4o"
            }
          )
        end

        it "uses current provider and api from version" do
          tools = helper.available_tools_for_provider

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(4)
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          tools = helper.available_tools_for_provider(provider: :unknown, api: :unknown)
          expect(tools).to eq([])
        end
      end
    end

    describe "#provider_supports_tools?" do
      it "returns true for OpenAI chat_completions" do
        expect(helper.provider_supports_tools?(provider: :openai, api: :chat_completions)).to be true
      end

      it "returns true for OpenAI responses" do
        expect(helper.provider_supports_tools?(provider: :openai, api: :responses)).to be true
      end

      it "returns true for OpenAI assistants" do
        expect(helper.provider_supports_tools?(provider: :openai, api: :assistants)).to be true
      end

      it "returns true for Anthropic messages" do
        expect(helper.provider_supports_tools?(provider: :anthropic, api: :messages)).to be true
      end

      it "returns false for unknown provider/API" do
        expect(helper.provider_supports_tools?(provider: :unknown, api: :unknown)).to be false
      end

      context "when provider and api are not specified" do
        before do
          @version.update!(
            model_config: {
              provider: "openai",
              api: "chat_completions",
              model: "gpt-4o"
            }
          )
        end

        it "uses current provider and api from version" do
          expect(helper.provider_supports_tools?).to be true
        end
      end
    end

    describe "#current_provider" do
      it "returns provider from version model_config" do
        @version.update!(model_config: { provider: "anthropic" })
        expect(helper.current_provider).to eq("anthropic")
      end

      it "returns default provider when version has no provider" do
        @version.update!(model_config: {})
        expect(helper.current_provider).to eq("openai")
      end

      it "returns openai when no version" do
        @version = nil
        expect(helper.current_provider).to eq("openai")
      end
    end

    describe "#current_api" do
      it "returns api from version model_config" do
        @version.update!(model_config: { api: "responses" })
        expect(helper.current_api).to eq("responses")
      end

      it "returns default api when version has no api" do
        @version.update!(model_config: {})
        expect(helper.current_api).to eq("chat_completions")
      end

      it "returns chat_completions when no version" do
        @version = nil
        expect(helper.current_api).to eq("chat_completions")
      end
    end

    describe "#current_model" do
      it "returns model from version model_config" do
        @version.update!(model_config: { model: "gpt-4-turbo" })
        expect(helper.current_model).to eq("gpt-4-turbo")
      end

      it "returns default model when version has no model" do
        @version.update!(model_config: {})
        expect(helper.current_model).to eq("gpt-4o")
      end

      it "returns gpt-4o when no version" do
        @version = nil
        expect(helper.current_model).to eq("gpt-4o")
      end
    end

    describe "#enabled_tools" do
      it "returns tools from version model_config" do
        @version.update!(model_config: { tools: [ "web_search", "functions" ] })
        expect(helper.enabled_tools).to eq([ "web_search", "functions" ])
      end

      it "returns empty array when version has no tools" do
        @version.update!(model_config: {})
        expect(helper.enabled_tools).to eq([])
      end

      it "returns empty array when no version" do
        @version = nil
        expect(helper.enabled_tools).to eq([])
      end
    end

    describe "#conversation_state_from_session" do
      it "returns conversation state from session" do
        session = {
          playground_conversation: {
            messages: [ { role: "user", content: "Hello" } ],
            previous_response_id: "resp_123",
            started_at: Time.current
          }
        }

        state = helper.conversation_state_from_session(session)

        expect(state[:messages]).to eq([ { role: "user", content: "Hello" } ])
        expect(state[:previous_response_id]).to eq("resp_123")
        expect(state[:started_at]).to be_present
      end

      it "returns default state when session has no conversation" do
        session = {}

        state = helper.conversation_state_from_session(session)

        expect(state[:messages]).to eq([])
        expect(state[:previous_response_id]).to be_nil
        expect(state[:started_at]).to be_nil
      end
    end
  end
end
