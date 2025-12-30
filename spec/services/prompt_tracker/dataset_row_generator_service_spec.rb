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
                  provider: "openai",
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
  end
end
