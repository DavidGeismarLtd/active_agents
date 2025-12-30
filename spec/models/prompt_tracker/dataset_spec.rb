# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe Dataset, type: :model do
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
        description: "Test prompt for datasets"
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

    describe "associations" do
      it { is_expected.to belong_to(:testable) }
      it { is_expected.to have_many(:dataset_rows).dependent(:destroy) }
      it { is_expected.to have_many(:test_runs).dependent(:nullify) }
    end

    describe "validations" do
      subject { version.datasets.build(name: "test_dataset", schema: version.variables_schema) }

      it { is_expected.to validate_presence_of(:name) }

      it "validates uniqueness of name scoped to prompt_version" do
        version.datasets.create!(name: "dataset1", schema: version.variables_schema)
        duplicate = version.datasets.build(name: "dataset1", schema: version.variables_schema)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end

      it "allows same name for different versions" do
        version2 = prompt.prompt_versions.create!(
          user_prompt: "Different {{name}}",
          version_number: 2,
          status: "draft",
          variables_schema: [ { "name" => "name", "type" => "string", "required" => true } ]
        )

        version.datasets.create!(name: "dataset1", schema: version.variables_schema)
        dataset2 = version2.datasets.build(name: "dataset1", schema: version2.variables_schema)

        expect(dataset2).to be_valid
      end

      it "validates schema is an array" do
        dataset = version.datasets.build(name: "test", schema: "not an array")

        expect(dataset).not_to be_valid
        expect(dataset.errors[:schema]).to include("must be an array")
      end

      it "validates schema matches prompt version" do
        dataset = version.datasets.build(
          name: "test",
          schema: [ { "name" => "wrong_var", "type" => "string" } ]
        )

        expect(dataset).not_to be_valid
        expect(dataset.errors[:schema]).to include("does not match testable's expected schema. Dataset is invalid.")
      end
    end

    describe "callbacks" do
      it "copies schema from version on create if blank" do
        dataset = version.datasets.create!(name: "test_dataset")

        expect(dataset.schema).to eq(version.variables_schema)
      end

      it "does not override provided schema" do
        custom_schema = version.variables_schema
        dataset = version.datasets.create!(name: "test_dataset", schema: custom_schema)

        expect(dataset.schema).to eq(custom_schema)
      end
    end

    describe "#row_count" do
      it "returns the number of rows in the dataset" do
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        expect(dataset.row_count).to eq(0)

        dataset.dataset_rows.create!(row_data: { "name" => "Alice", "issue" => "billing" })
        dataset.dataset_rows.create!(row_data: { "name" => "Bob", "issue" => "refund" })

        expect(dataset.row_count).to eq(2)
      end
    end

    describe "#schema_valid?" do
      it "returns true when schema matches version schema" do
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        expect(dataset.schema_valid?).to be true
      end

      it "returns false when schema does not match version schema" do
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        # Change version schema
        version.update!(
          variables_schema: [
            { "name" => "name", "type" => "string", "required" => true },
            { "name" => "different_var", "type" => "string", "required" => false }
          ]
        )

        expect(dataset.reload.schema_valid?).to be false
      end

      it "returns false when version has no schema" do
        # Create dataset with valid schema first
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        # Then update version to have no schema (making dataset invalid)
        version.update!(variables_schema: [])

        expect(dataset.reload.schema_valid?).to be false
      end
    end

    describe "#variable_names" do
      it "returns list of variable names from schema" do
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        expect(dataset.variable_names).to eq([ "name", "issue" ])
      end

      it "returns empty array for empty schema" do
        # Create dataset with valid schema first
        dataset = version.datasets.create!(name: "test_dataset", schema: version.variables_schema)

        # Manually set schema to empty (bypassing validation)
        dataset.update_column(:schema, [])

        expect(dataset.variable_names).to eq([])
      end
    end
  end
end
