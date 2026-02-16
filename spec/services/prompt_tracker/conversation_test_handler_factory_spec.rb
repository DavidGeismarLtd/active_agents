# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ConversationTestHandlerFactory, type: :service do
    describe ".build" do
      context "with OpenAI Response API" do
        let(:model_config) do
          {
            provider: "openai",
            api: "responses",
            model: "gpt-4o"
          }
        end

        it "returns Responses::SimulatedConversationRunner" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::Responses::SimulatedConversationRunner)
        end

        it "passes model_config to handler" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler.model_config[:provider]).to eq("openai")
          expect(handler.model_config[:api]).to eq("responses")
          expect(handler.model_config[:model]).to eq("gpt-4o")
        end

        it "passes use_real_llm flag to handler" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: true
          )

          expect(handler.use_real_llm).to be true
        end
      end

      context "with OpenAI Chat Completions API" do
        let(:model_config) do
          {
            provider: "openai",
            api: "chat_completions",
            model: "gpt-4o"
          }
        end

        it "returns ChatCompletions::SimulatedConversationRunner" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::ChatCompletions::SimulatedConversationRunner)
        end
      end

      context "with OpenAI Assistants API" do
        let(:model_config) do
          {
            provider: "openai",
            api: "assistants",
            model: "gpt-4o",
            assistant_id: "asst_abc123"
          }
        end

        it "returns Assistants::SimulatedConversationRunner" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::Assistants::SimulatedConversationRunner)
        end

        it "passes model_config to handler" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler.model_config[:provider]).to eq("openai")
          expect(handler.model_config[:api]).to eq("assistants")
          expect(handler.model_config[:assistant_id]).to eq("asst_abc123")
        end
      end

      context "with Anthropic Messages API" do
        let(:model_config) do
          {
            provider: "anthropic",
            api: "messages",
            model: "claude-3-5-sonnet-20241022"
          }
        end

        it "returns ChatCompletions::SimulatedConversationRunner" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::ChatCompletions::SimulatedConversationRunner)
        end
      end

      context "with Google Gemini API" do
        let(:model_config) do
          {
            provider: "google",
            api: "gemini",
            model: "gemini-2.0-flash-exp"
          }
        end

        it "returns ChatCompletions::SimulatedConversationRunner" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::ChatCompletions::SimulatedConversationRunner)
        end
      end

      context "with unknown API type" do
        let(:model_config) do
          {
            provider: "custom_provider",
            api: "custom_api",
            model: "custom-model"
          }
        end

        it "returns ChatCompletions::SimulatedConversationRunner as fallback" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false
          )

          expect(handler).to be_a(TestRunners::Openai::ChatCompletions::SimulatedConversationRunner)
        end
      end

      context "with testable parameter" do
        let(:model_config) do
          {
            provider: "openai",
            api: "chat_completions",
            model: "gpt-4o"
          }
        end

        let(:testable) { double("PromptVersion") }

        it "passes testable to handler" do
          handler = described_class.build(
            model_config: model_config,
            use_real_llm: false,
            testable: testable
          )

          expect(handler.testable).to eq(testable)
        end
      end

      context "with invalid model_config" do
        it "raises ArgumentError when provider is missing" do
          expect do
            described_class.build(
              model_config: { api: "chat_completions", model: "gpt-4o" },
              use_real_llm: false
            )
          end.to raise_error(ArgumentError, /must include :provider/)
        end

        it "raises ArgumentError when api is missing" do
          expect do
            described_class.build(
              model_config: { provider: "openai", model: "gpt-4o" },
              use_real_llm: false
            )
          end.to raise_error(ArgumentError, /must include :api/)
        end
      end
    end
  end
end
