# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe TestGeneratorService do
    let(:prompt) { create(:prompt) }
    let(:prompt_version) do
      create(:prompt_version,
             prompt: prompt,
             system_prompt: "You are a helpful assistant.",
             user_prompt: "Help me with {{ topic }}",
             variables_schema: [ { "name" => "topic", "type" => "string", "required" => true } ])
    end

    describe ".generate" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_response) do
        double("response", content: {
          tests: [
            {
              name: "test_basic_response",
              description: "Tests basic response quality",
              reasoning: "Validates core functionality",
              evaluator_configs: [
                {
                  evaluator_key: "llm_judge",
                  config_json: '{"custom_instructions": "Check if response is helpful"}'
                }
              ]
            },
            {
              name: "test_length_validation",
              description: "Tests response has appropriate length",
              reasoning: "Ensures responses aren't too short",
              evaluator_configs: [
                {
                  evaluator_key: "length",
                  config_json: '{"min_length": 50}'
                }
              ]
            }
          ],
          overall_reasoning: "Comprehensive test suite covering quality and length"
        })
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        # Stub configuration methods for all contexts (needed for view rendering during broadcasts)
        allow(PromptTracker.configuration).to receive(:default_model_for).and_call_original
        allow(PromptTracker.configuration).to receive(:default_temperature_for).and_call_original
      end

      it "generates tests for the prompt version" do
        result = described_class.generate(prompt_version: prompt_version)

        expect(result[:count]).to eq(2)
        expect(result[:tests].size).to eq(2)
        expect(result[:overall_reasoning]).to be_present
      end

      it "creates Test records in the database" do
        expect {
          described_class.generate(prompt_version: prompt_version)
        }.to change(Test, :count).by(2)
      end

      it "creates EvaluatorConfig records for each test" do
        expect {
          described_class.generate(prompt_version: prompt_version)
        }.to change(EvaluatorConfig, :count).by(2)
      end

      it "associates tests with the prompt version" do
        result = described_class.generate(prompt_version: prompt_version)

        result[:tests].each do |test|
          expect(test.testable).to eq(prompt_version)
        end
      end

      it "stores AI generation metadata" do
        result = described_class.generate(prompt_version: prompt_version)

        test = result[:tests].first
        expect(test.metadata["ai_generated"]).to be true
        expect(test.metadata["reasoning"]).to be_present
        expect(test.metadata["generated_at"]).to be_present
        expect(test.metadata["generation_model"]).to be_present
        expect(test.metadata["generation_prompt"]).to be_present
      end

      it "stores the generation prompt in metadata" do
        result = described_class.generate(prompt_version: prompt_version, instructions: "Focus on edge cases")

        test = result[:tests].first
        generation_prompt = test.metadata["generation_prompt"]

        expect(generation_prompt).to be_present
        expect(generation_prompt).to include("PROMPT TO TEST")
        expect(generation_prompt).to include("AVAILABLE EVALUATORS")
        expect(generation_prompt).to include("Focus on edge cases")
      end

      it "passes user instructions to the LLM" do
        expect(mock_chat).to receive(:ask).with(
          a_string_including("Focus on edge cases")
        ).and_return(mock_response)

        described_class.generate(
          prompt_version: prompt_version,
          instructions: "Focus on edge cases"
        )
      end

      it "uses the configured model from context" do
        # Stub only :test_generation context, allow others to call original
        allow(PromptTracker.configuration).to receive(:default_model_for).and_call_original
        allow(PromptTracker.configuration).to receive(:default_model_for)
          .with(:test_generation).and_return("gpt-4o-custom")
        allow(PromptTracker.configuration).to receive(:default_temperature_for).and_call_original
        allow(PromptTracker.configuration).to receive(:default_temperature_for)
          .with(:test_generation).and_return(0.8)

        expect(RubyLLM).to receive(:chat).with(model: "gpt-4o-custom").and_return(mock_chat)
        expect(mock_chat).to receive(:with_temperature).with(0.8).and_return(mock_chat)

        described_class.generate(prompt_version: prompt_version)
      end

      it "falls back to defaults when context not configured" do
        # Stub only :test_generation context, allow others to call original
        allow(PromptTracker.configuration).to receive(:default_model_for).and_call_original
        allow(PromptTracker.configuration).to receive(:default_model_for)
          .with(:test_generation).and_return(nil)
        allow(PromptTracker.configuration).to receive(:default_temperature_for).and_call_original
        allow(PromptTracker.configuration).to receive(:default_temperature_for)
          .with(:test_generation).and_return(nil)

        expect(RubyLLM).to receive(:chat).with(model: "gpt-4o").and_return(mock_chat)
        expect(mock_chat).to receive(:with_temperature).with(0.7).and_return(mock_chat)

        described_class.generate(prompt_version: prompt_version)
      end

      it "includes prompt context in the generation prompt" do
        expect(mock_chat).to receive(:ask).with(
          a_string_including("You are a helpful assistant.")
        ).and_return(mock_response)

        described_class.generate(prompt_version: prompt_version)
      end

      it "includes variables in the generation prompt" do
        expect(mock_chat).to receive(:ask).with(
          a_string_including("topic")
        ).and_return(mock_response)

        described_class.generate(prompt_version: prompt_version)
      end

      it "includes available evaluators in the generation prompt" do
        expect(mock_chat).to receive(:ask).with(
          a_string_including("AVAILABLE EVALUATORS")
        ).and_return(mock_response)

        described_class.generate(prompt_version: prompt_version)
      end

      context "when prompt version has vector stores configured" do
        let(:prompt_version_with_vector_stores) do
          create(:prompt_version,
                 prompt: prompt,
                 model_config: {
                   "provider" => "openai",
                   "api" => "assistants",
                   "model" => "gpt-4o",
                   "tools" => [ "file_search" ],
                   "tool_config" => {
                     "file_search" => {
                       "vector_stores" => [
                         { "id" => "vs_123", "name" => "Knowledge Base" },
                         { "id" => "vs_456", "name" => "Documentation" }
                       ]
                     }
                   }
                 })
        end

        it "includes vector stores in the generation prompt" do
          expect(mock_chat).to receive(:ask).with(
            a_string_including("Vector Stores (File Search)")
              .and(a_string_including("Knowledge Base"))
              .and(a_string_including("vs_123"))
          ).and_return(mock_response)

          described_class.generate(prompt_version: prompt_version_with_vector_stores)
        end

        it "includes file_search guidelines in the prompt" do
          expect(mock_chat).to receive(:ask).with(
            a_string_including("If vector stores are configured, ALWAYS include at least one test with file_search evaluator")
          ).and_return(mock_response)

          described_class.generate(prompt_version: prompt_version_with_vector_stores)
        end
      end

      context "when evaluator key is not found in registry" do
        let(:mock_response_with_invalid) do
          double("response", content: {
            tests: [
              {
                name: "test_with_invalid_evaluator",
                description: "Test with invalid evaluator",
                reasoning: "Testing",
                evaluator_configs: [
                  { evaluator_key: "nonexistent_evaluator", config_json: "{}" },
                  { evaluator_key: "length", config_json: '{"min_length": 10}' }
                ]
              }
            ],
            overall_reasoning: "Test"
          })
        end

        it "skips invalid evaluators but creates valid ones" do
          allow(mock_chat).to receive(:ask).and_return(mock_response_with_invalid)

          result = described_class.generate(prompt_version: prompt_version)

          test = result[:tests].first
          expect(test.evaluator_configs.count).to eq(1)
          expect(test.evaluator_configs.first.evaluator_type).to include("LengthEvaluator")
        end
      end

      context "when LLM returns string test names" do
        let(:string_response) do
          double("response", content: {
            tests: [ "test_name_only", "another_test_name" ],
            overall_reasoning: "Test"
          })
        end

        let(:expanded_response) do
          double("response", content: {
            tests: [
              {
                name: "test_name_only",
                description: "Test description",
                reasoning: "Reasoning",
                evaluator_configs: [
                  { evaluator_key: "length", config_json: '{"min_length": 10}' }
                ]
              }
            ],
            overall_reasoning: "Expanded test"
          })
        end

        it "makes a follow-up call to expand string test names" do
          # First call returns strings, second call returns full objects
          allow(mock_chat).to receive(:ask).and_return(string_response, expanded_response)

          result = described_class.generate(prompt_version: prompt_version)

          # Verify the follow-up call was made
          expect(mock_chat).to have_received(:ask).twice
          expect(result[:tests].first.name).to eq("test_name_only")
        end
      end
    end
  end
end
