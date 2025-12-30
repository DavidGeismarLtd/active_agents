# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe DatasetRow, type: :model do
    # Disable Turbo Stream broadcasts in tests to avoid route helper issues
    before do
      allow_any_instance_of(DatasetRow).to receive(:broadcast_prepend_to_dataset)
      allow_any_instance_of(DatasetRow).to receive(:broadcast_replace_to_dataset)
      allow_any_instance_of(DatasetRow).to receive(:broadcast_remove_to_dataset)
    end

    # Setup
    let(:prompt) do
      Prompt.create!(
        name: "test_prompt",
        description: "Test prompt for dataset rows"
      )
    end

    let(:version) do
      prompt.prompt_versions.create!(
        user_prompt: "Hello {{name}}, your issue is {{issue}}",
        version_number: 1,
        status: "active",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true },
          { "name" => "issue", "type" => "string", "required" => false }
        ]
      )
    end

    let(:dataset) do
      version.datasets.create!(
        name: "test_dataset",
        schema: version.variables_schema
      )
    end

    describe "associations" do
      it { is_expected.to belong_to(:dataset) }
      it { is_expected.to have_many(:test_runs).dependent(:nullify) }
    end

    describe "validations" do
      it { is_expected.to validate_presence_of(:row_data) }
      it { is_expected.to validate_presence_of(:source) }
      it { is_expected.to validate_inclusion_of(:source).in_array(%w[manual llm_generated imported]) }

      it "validates row_data is a hash" do
        row = dataset.dataset_rows.build(row_data: "not a hash", source: "manual")

        expect(row).not_to be_valid
        expect(row.errors[:row_data]).to include("must be a hash")
      end

      it "validates row_data matches schema - missing required variables" do
        row = dataset.dataset_rows.build(
          row_data: { "issue" => "billing" }, # missing required "name"
          source: "manual"
        )

        expect(row).not_to be_valid
        expect(row.errors[:row_data]).to include("missing required variables: name")
      end

      it "validates row_data matches schema - extra variables" do
        row = dataset.dataset_rows.build(
          row_data: {
            "name" => "Alice",
            "issue" => "billing",
            "extra_var" => "not in schema"
          },
          source: "manual"
        )

        expect(row).not_to be_valid
        expect(row.errors[:row_data]).to include("contains unknown variables: extra_var")
      end

      it "allows valid row_data with all required variables" do
        row = dataset.dataset_rows.build(
          row_data: { "name" => "Alice", "issue" => "billing" },
          source: "manual"
        )

        expect(row).to be_valid
      end

      it "allows valid row_data with only required variables" do
        row = dataset.dataset_rows.build(
          row_data: { "name" => "Alice" },
          source: "manual"
        )

        expect(row).to be_valid
      end
    end

    describe "scopes" do
      before do
        dataset.dataset_rows.create!(row_data: { "name" => "Alice" }, source: "manual")
        dataset.dataset_rows.create!(row_data: { "name" => "Bob" }, source: "llm_generated")
        dataset.dataset_rows.create!(row_data: { "name" => "Charlie" }, source: "imported")
      end

      it "filters by manual source" do
        expect(dataset.dataset_rows.manual.count).to eq(1)
        expect(dataset.dataset_rows.manual.first.get_variable("name")).to eq("Alice")
      end

      it "filters by llm_generated source" do
        expect(dataset.dataset_rows.llm_generated.count).to eq(1)
        expect(dataset.dataset_rows.llm_generated.first.get_variable("name")).to eq("Bob")
      end

      it "filters by imported source" do
        expect(dataset.dataset_rows.imported.count).to eq(1)
        expect(dataset.dataset_rows.imported.first.get_variable("name")).to eq("Charlie")
      end

      it "orders by recent" do
        rows = dataset.dataset_rows.recent
        expect(rows.first.get_variable("name")).to eq("Charlie")
        expect(rows.last.get_variable("name")).to eq("Alice")
      end
    end

    describe "#get_variable" do
      let(:row) do
        dataset.dataset_rows.create!(
          row_data: { "name" => "Alice", "issue" => "billing" },
          source: "manual"
        )
      end

      it "returns variable value by string key" do
        expect(row.get_variable("name")).to eq("Alice")
        expect(row.get_variable("issue")).to eq("billing")
      end

      it "returns variable value by symbol key" do
        expect(row.get_variable(:name)).to eq("Alice")
        expect(row.get_variable(:issue)).to eq("billing")
      end

      it "returns nil for non-existent variable" do
        expect(row.get_variable("nonexistent")).to be_nil
      end
    end

    describe "#set_variable" do
      let(:row) do
        dataset.dataset_rows.create!(
          row_data: { "name" => "Alice", "issue" => "billing" },
          source: "manual"
        )
      end

      it "sets variable value by string key" do
        row.set_variable("name", "Bob")
        expect(row.row_data["name"]).to eq("Bob")
      end

      it "sets variable value by symbol key" do
        row.set_variable(:issue, "refund")
        expect(row.row_data["issue"]).to eq("refund")
      end
    end
  end
end
