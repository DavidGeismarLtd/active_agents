# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe RunTestJob, type: :job do
    # Disable Turbo Stream broadcasts in tests to avoid route helper issues
    before do
      allow_any_instance_of(DatasetRow).to receive(:broadcast_prepend_to_dataset)
      allow_any_instance_of(DatasetRow).to receive(:broadcast_replace_to_dataset)
      allow_any_instance_of(DatasetRow).to receive(:broadcast_remove_to_dataset)
      allow_any_instance_of(TestRun).to receive(:broadcast_status_change)
    end

    let(:prompt) { create(:prompt, name: "test_prompt") }
    let(:version) do
      create(:prompt_version,
             prompt: prompt,
             user_prompt: "Hello {{name}}",
             variables_schema: [
               { "name" => "name", "type" => "string", "required" => true }
             ],
             model_config: {
               "provider" => "openai",
               "api" => "chat_completions",
               "model" => "gpt-4-0613",
               "temperature" => 0.7
             })
    end
    let(:dataset) do
      create(:dataset,
             testable: version,
             name: "test_dataset",
             schema: version.variables_schema)
    end
    let(:dataset_row) do
      create(:dataset_row,
             dataset: dataset,
             row_data: { "name" => "John" },
             source: "manual")
    end
    let(:test) do
      create(:test,
             testable: version)
    end
    let(:test_run) do
      create(:test_run,
             test: test,
             dataset_row: dataset_row,
             status: "running",
             cost_usd: nil)
    end

    let(:mock_response) do
      instance_double(
        RubyLLM::Message,
        content: "Hello John! How can I help you today?",
        model_id: "gpt-4-0613",
        input_tokens: 10,
        output_tokens: 20,
        cached_tokens: 0,
        cache_creation_tokens: 0
      )
    end

    let(:mock_model_info) do
      double(
        "RubyLLM::ModelInfo",
        input_price_per_million: 30.0,
        output_price_per_million: 60.0
      )
    end

    before do
      # Mock LlmClientService to return the mock response
      allow(PromptTracker::LlmClientService).to receive(:call).and_return({
        text: mock_response.content,
        usage: {
          prompt_tokens: mock_response.input_tokens,
          completion_tokens: mock_response.output_tokens,
          total_tokens: mock_response.input_tokens + mock_response.output_tokens
        },
        model: mock_response.model_id,
        raw: mock_response
      })
    end

    describe "#perform" do
      context "with mock LLM" do
        it "stores output_data in test run" do
          described_class.new.perform(test_run.id, use_real_llm: false)

          test_run.reload
          expect(test_run.output_data).to be_present
          expect(test_run.output_data["messages"]).to be_an(Array)
          expect(test_run.output_data["messages"].length).to eq(2) # user + assistant
        end

        it "updates test run with execution time" do
          described_class.new.perform(test_run.id, use_real_llm: false)

          test_run.reload
          expect(test_run.execution_time_ms).to be_present
          expect(test_run.execution_time_ms).to be >= 0
        end

        it "does not calculate cost when use_real_llm is false" do
          described_class.new.perform(test_run.id, use_real_llm: false)

          test_run.reload
          # Cost calculation is skipped when use_real_llm is false
          expect(test_run.cost_usd).to be_nil
        end

        it "updates test run status to passed when no evaluators" do
          described_class.new.perform(test_run.id, use_real_llm: false)

          test_run.reload
          expect(test_run.status).to eq("passed")
          expect(test_run.passed).to be true
        end
      end

      context "with real LLM" do
        it "stores output_data in test run" do
          allow(RubyLLM.models).to receive(:find).and_return(mock_model_info)

          described_class.new.perform(test_run.id, use_real_llm: true)

          test_run.reload
          expect(test_run.output_data).to be_present
          expect(test_run.output_data["messages"]).to be_an(Array)
          expect(test_run.output_data["tokens"]).to be_present
        end

        it "calculates cost using RubyLLM model registry" do
          allow(RubyLLM.models).to receive(:find).and_return(mock_model_info)

          described_class.new.perform(test_run.id, use_real_llm: true)

          test_run.reload
          # Mock returns 10 prompt tokens and 20 completion tokens
          # Expected cost: (10 * 30.0 / 1_000_000) + (20 * 60.0 / 1_000_000)
          # = 0.0003 + 0.0012 = 0.0015
          expect(test_run.cost_usd).to be_within(0.000001).of(0.0015)
        end

        it "handles missing pricing information gracefully" do
          allow(RubyLLM.models).to receive(:find).and_return(nil)

          described_class.new.perform(test_run.id, use_real_llm: true)

          test_run.reload
          expect(test_run.cost_usd).to be_nil
        end

        it "handles model info without pricing" do
          model_without_pricing = double("RubyLLM::ModelInfo", input_price_per_million: nil, output_price_per_million: nil)
          allow(RubyLLM.models).to receive(:find).and_return(model_without_pricing)

          described_class.new.perform(test_run.id, use_real_llm: true)

          test_run.reload
          expect(test_run.cost_usd).to be_nil
        end
      end

      context "with evaluators" do
        before do
          create(:evaluator_config,
                 configurable: test,
                 evaluator_key: "keyword",
                 config: { required_keywords: [ "Mock", "testing" ] })
        end

        it "runs evaluators and updates test run" do
          described_class.new.perform(test_run.id, use_real_llm: false)

          test_run.reload
          expect(test_run.status).to eq("passed")
          expect(test_run.passed).to be true
          expect(test_run.metadata["evaluator_results"]).to be_an(Array)
          expect(test_run.metadata["evaluator_results"].length).to eq(1)
          expect(test_run.metadata["evaluator_results"].first["passed"]).to be true
        end
      end
    end
  end
end
