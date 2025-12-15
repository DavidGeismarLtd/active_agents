# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe PromptEnhancerService do
    describe ".enhance" do
      let(:mock_response) do
        {
          text: {
            system_prompt: "You are a professional customer support agent. Be helpful, empathetic, and concise.",
            user_prompt: "Help {{ customer_name }} with their {{ issue_type }} issue: {{ issue_description }}",
            suggested_variables: [ "customer_name", "issue_type", "issue_description" ],
            explanation: "Enhanced prompt with clear role definition and structured variables"
          }.to_json
        }
      end

      before do
        allow(LlmClientService).to receive(:call_with_schema).and_return(mock_response)
      end

      context "enhancement mode (existing content)" do
        it "enhances existing prompts" do
          result = described_class.enhance(
            system_prompt: "You are helpful.",
            user_prompt: "Help the user.",
            context: "customer support"
          )

          expect(result[:system_prompt]).to include("professional customer support agent")
          expect(result[:user_prompt]).to include("{{ customer_name }}")
          expect(result[:suggested_variables]).to include("customer_name", "issue_type")
          expect(result[:explanation]).to be_present
        end

        it "calls LLM with enhancement prompt" do
          described_class.enhance(
            system_prompt: "You are helpful.",
            user_prompt: "Help the user."
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:prompt]).to include("Improve the following prompt")
            expect(args[:prompt]).to include("You are helpful.")
            expect(args[:model]).to eq("gpt-4o-mini")
          end
        end

        it "includes context in the prompt" do
          described_class.enhance(
            system_prompt: "You are helpful.",
            user_prompt: "Help the user.",
            context: "email generator"
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:prompt]).to include("email generator")
          end
        end
      end

      context "generation mode (empty prompts)" do
        let(:generation_response) do
          {
            text: {
              system_prompt: "You are an expert email writer. Create professional, clear emails.",
              user_prompt: "Write an email to {{ recipient_name }} about {{ subject }}. Tone: {{ tone }}",
              suggested_variables: [ "recipient_name", "subject", "tone" ],
              explanation: "Generated professional email writing prompt with key variables"
            }.to_json
          }
        end

        before do
          allow(LlmClientService).to receive(:call_with_schema).and_return(generation_response)
        end

        it "generates prompts from scratch" do
          result = described_class.enhance(
            system_prompt: "",
            user_prompt: "",
            context: "email generator"
          )

          expect(result[:system_prompt]).to include("email writer")
          expect(result[:user_prompt]).to include("{{ recipient_name }}")
          expect(result[:suggested_variables]).to include("recipient_name", "subject")
        end

        it "calls LLM with generation prompt" do
          described_class.enhance(
            system_prompt: "",
            user_prompt: "",
            context: "email generator"
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:prompt]).to include("Generate a professional prompt template")
            expect(args[:prompt]).to include("email generator")
          end
        end

        it "uses default context when none provided" do
          described_class.enhance(
            system_prompt: "",
            user_prompt: ""
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:prompt]).to include("general-purpose assistant")
          end
        end
      end

      context "schema validation" do
        it "uses RubyLLM schema for structured output" do
          described_class.enhance(
            system_prompt: "Test",
            user_prompt: "Test"
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:schema]).to be < RubyLLM::Schema
          end
        end
      end

      context "error handling" do
        it "raises error when LLM call fails" do
          allow(LlmClientService).to receive(:call_with_schema).and_raise(StandardError.new("API error"))

          expect {
            described_class.enhance(
              system_prompt: "Test",
              user_prompt: "Test"
            )
          }.to raise_error(StandardError, "API error")
        end
      end

      context "configuration" do
        it "uses configured model from ENV" do
          allow(ENV).to receive(:fetch).with("PROMPT_ENHANCER_MODEL", anything).and_return("gpt-4")
          stub_const("#{described_class}::DEFAULT_MODEL", "gpt-4")

          described_class.enhance(
            system_prompt: "Test",
            user_prompt: "Test"
          )

          expect(LlmClientService).to have_received(:call_with_schema) do |args|
            expect(args[:model]).to eq("gpt-4")
          end
        end
      end
    end
  end
end
