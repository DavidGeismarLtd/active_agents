# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/schema"

RSpec.describe PromptTracker::DatasetRowGeneratorService do
  let(:prompt) { create(:prompt) }
  let(:version) do
    create(:prompt_version,
           prompt: prompt,
           variables_schema: [
             { "name" => "customer_name", "type" => "string", "required" => true, "description" => "Customer's full name" },
             { "name" => "issue_type", "type" => "string", "required" => true, "description" => "Type of support issue" },
             { "name" => "priority", "type" => "number", "required" => false, "description" => "Priority level 1-5" }
           ])
  end
  let(:dataset) { create(:dataset, testable: version) }

  describe ".generate" do
    context "with valid parameters" do
      let(:count) { 5 }
      let(:instructions) { "Focus on edge cases" }
      let(:model) { "gpt-4o" }

      let(:mock_llm_response) do
        {
          text: {
            rows: [
              { "customer_name" => "Alice Smith", "issue_type" => "billing", "priority" => 1 },
              { "customer_name" => "Bob Jones", "issue_type" => "technical", "priority" => 3 },
              { "customer_name" => "Charlie Brown", "issue_type" => "refund", "priority" => 2 },
              { "customer_name" => "Diana Prince", "issue_type" => "account", "priority" => 5 },
              { "customer_name" => "Eve Adams", "issue_type" => "general", "priority" => 1 }
            ]
          }.to_json
        }
      end

      before do
        # Set up dataset_generation context configuration
        PromptTracker.configuration.contexts = {
          dataset_generation: {
            description: "Generating test dataset rows via LLM",
            default_provider: :openai,
            default_api: :chat_completions,
            default_model: "gpt-4o"
          }
        }

        allow(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .and_return(mock_llm_response)

        # Disable Turbo Stream broadcasts in tests to avoid route helper issues
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_prepend_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_replace_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_remove_to_dataset)
      end

      it "generates the correct number of rows" do
        rows = described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )

        expect(rows.count).to eq(5)
      end

      it "creates DatasetRow records with correct source" do
        rows = described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )

        expect(rows).to all(be_a(PromptTracker::DatasetRow))
        expect(rows).to all(have_attributes(source: "llm_generated"))
      end

      it "stores generation metadata" do
        rows = described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )

        first_row = rows.first
        expect(first_row.metadata["generation_model"]).to eq(model)
        expect(first_row.metadata["generation_instructions"]).to eq(instructions)
        expect(first_row.metadata["generated_at"]).to be_present
      end

      it "stores row_data matching the schema" do
        rows = described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )

        first_row = rows.first
        expect(first_row.row_data).to include(
          "customer_name" => "Alice Smith",
          "issue_type" => "billing",
          "priority" => 1
        )
      end

      it "calls LlmClientService with correct parameters" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .with(hash_including(
                  provider: :openai,
                  model: model,
                  temperature: 0.8
                ))
          .and_return(mock_llm_response)

        described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )
      end

      it "includes custom instructions in the prompt" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema) do |args|
          expect(args[:prompt]).to include("CUSTOM INSTRUCTIONS")
          expect(args[:prompt]).to include(instructions)
          mock_llm_response
        end

        described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )
      end

      it "includes schema information in the prompt" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema) do |args|
          expect(args[:prompt]).to include("customer_name")
          expect(args[:prompt]).to include("issue_type")
          expect(args[:prompt]).to include("priority")
          mock_llm_response
        end

        described_class.generate(
          dataset: dataset,
          count: count,
          instructions: instructions,
          model: model
        )
      end
    end

    context "with invalid parameters" do
      it "raises error when count is too low" do
        expect do
          described_class.generate(dataset: dataset, count: 0)
        end.to raise_error(ArgumentError, /Count must be between/)
      end

      it "raises error when count is too high" do
        expect do
          described_class.generate(dataset: dataset, count: 101)
        end.to raise_error(ArgumentError, /Count must be between/)
      end

      it "raises error when dataset is nil" do
        expect do
          described_class.generate(dataset: nil, count: 10)
        end.to raise_error(ArgumentError, /Dataset is required/)
      end

      it "raises error when dataset has no schema" do
        # Bypass validations to set empty schema
        dataset.update_column(:schema, [])

        expect do
          described_class.generate(dataset: dataset, count: 10)
        end.to raise_error(ArgumentError, /must have a valid schema/)
      end
    end

    context "when LLM returns invalid response" do
      before do
        allow(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .and_return({ text: "invalid json" })
      end

      it "raises error for invalid JSON" do
        expect do
          described_class.generate(dataset: dataset, count: 5)
        end.to raise_error(/Failed to parse LLM response/)
      end
    end

    context "when LLM returns response without rows array" do
      before do
        allow(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .and_return({ text: { "data" => [] }.to_json })
      end

      it "raises error for missing rows" do
        expect do
          described_class.generate(dataset: dataset, count: 5)
        end.to raise_error(/did not include 'rows' array/)
      end
    end

    context "when testable has function calling configured" do
      let(:version_with_functions) do
        create(:prompt_version,
               prompt: prompt,
               variables_schema: [
                 { "name" => "user_query", "type" => "string", "required" => true, "description" => "User's question" }
               ],
               model_config: {
                 "provider" => "openai",
                 "model" => "gpt-4o",
                 "tool_config" => {
                   "functions" => [
                     {
                       "name" => "get_weather",
                       "description" => "Get weather for a location",
                       "parameters" => {
                         "type" => "object",
                         "properties" => {
                           "location" => { "type" => "string" }
                         }
                       }
                     },
                     {
                       "name" => "search_flights",
                       "description" => "Search for flights",
                       "parameters" => {
                         "type" => "object",
                         "properties" => {
                           "from" => { "type" => "string" },
                           "to" => { "type" => "string" }
                         }
                       }
                     }
                   ]
                 }
               })
      end

      let(:dataset_with_functions) { create(:dataset, testable: version_with_functions) }

      let(:mock_llm_response_with_functions) do
        {
          text: {
            rows: [
              {
                "user_query" => "What's the weather in NYC?",
                "mock_function_outputs" => {
                  "get_weather" => {
                    "location" => "New York, NY",
                    "temperature" => 72,
                    "condition" => "Sunny"
                  }
                }
              },
              {
                "user_query" => "Find flights from NYC to LAX",
                "mock_function_outputs" => {
                  "search_flights" => {
                    "flights" => [
                      { "airline" => "AA", "price" => 299 },
                      { "airline" => "UA", "price" => 315 }
                    ]
                  }
                }
              }
            ]
          }.to_json
        }
      end

      before do
        allow(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .and_return(mock_llm_response_with_functions)

        # Disable Turbo Stream broadcasts
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_prepend_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_replace_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_remove_to_dataset)
      end

      it "includes function context in the generation prompt" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema) do |args|
          expect(args[:prompt]).to include("FUNCTION CALLING")
          expect(args[:prompt]).to include("get_weather")
          expect(args[:prompt]).to include("search_flights")
          mock_llm_response_with_functions
        end

        described_class.generate(
          dataset: dataset_with_functions,
          count: 2,
          model: "gpt-4o"
        )
      end

      it "generates rows with mock_function_outputs" do
        rows = described_class.generate(
          dataset: dataset_with_functions,
          count: 2,
          model: "gpt-4o"
        )

        first_row = rows.first
        expect(first_row.row_data["mock_function_outputs"]).to be_present
        expect(first_row.row_data["mock_function_outputs"]["get_weather"]).to eq({
          "location" => "New York, NY",
          "temperature" => 72,
          "condition" => "Sunny"
        })

        second_row = rows.second
        expect(second_row.row_data["mock_function_outputs"]).to be_present
        expect(second_row.row_data["mock_function_outputs"]["search_flights"]).to be_present
        expect(second_row.row_data["mock_function_outputs"]["search_flights"]["flights"]).to be_an(Array)
      end

      it "includes mock_function_outputs field in schema" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema) do |args|
          # The schema should be a RubyLLM::Schema class
          schema_class = args[:schema]
          expect(schema_class).to be < RubyLLM::Schema

          # Verify the schema can be instantiated (validates structure)
          expect { schema_class.new }.not_to raise_error

          mock_llm_response_with_functions
        end

        described_class.generate(
          dataset: dataset_with_functions,
          count: 2,
          model: "gpt-4o"
        )
      end
    end

    context "when testable has no function calling configured" do
      let(:mock_llm_response_without_functions) do
        {
          text: {
            rows: [
              { "customer_name" => "Alice Smith", "issue_type" => "billing", "priority" => 1 }
            ]
          }.to_json
        }
      end

      before do
        allow(PromptTracker::LlmClientService).to receive(:call_with_schema)
          .and_return(mock_llm_response_without_functions)

        # Disable Turbo Stream broadcasts
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_prepend_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_replace_to_dataset)
        allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_remove_to_dataset)
      end

      it "does not include function context in the generation prompt" do
        expect(PromptTracker::LlmClientService).to receive(:call_with_schema) do |args|
          expect(args[:prompt]).not_to include("FUNCTION CALLING")
          mock_llm_response_without_functions
        end

        described_class.generate(
          dataset: dataset,
          count: 1,
          model: "gpt-4o"
        )
      end

      it "generates rows without mock_function_outputs" do
        rows = described_class.generate(
          dataset: dataset,
          count: 1,
          model: "gpt-4o"
        )

        first_row = rows.first
        expect(first_row.row_data["mock_function_outputs"]).to be_nil
      end
    end
  end
end
