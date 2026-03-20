# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe FunctionExecution, type: :model do
    # Setup
    let(:function_definition) do
      FunctionDefinition.create!(
        name: "test_function",
        description: "A test function",
        code: "def execute(x:)\n  x * 2\nend",
        parameters: { "type" => "object", "properties" => { "x" => { "type" => "number" } } },
        language: "ruby"
      )
    end

    let(:valid_attributes) do
      {
        function_definition: function_definition,
        arguments: { "x" => 5 },
        result: { "value" => 10 },
        success: true,
        execution_time_ms: 100,
        executed_at: Time.current
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        execution = FunctionExecution.new(valid_attributes)
        expect(execution).to be_valid
      end

      it "requires function_definition" do
        execution = FunctionExecution.new(valid_attributes.except(:function_definition))
        expect(execution).not_to be_valid
        expect(execution.errors[:function_definition]).to include("must exist")
      end

      it "requires arguments" do
        execution = FunctionExecution.new(valid_attributes.except(:arguments))
        expect(execution).not_to be_valid
        expect(execution.errors[:arguments]).to include("can't be blank")
      end

      it "requires executed_at" do
        execution = FunctionExecution.new(valid_attributes.except(:executed_at))
        expect(execution).not_to be_valid
        expect(execution.errors[:executed_at]).to include("can't be blank")
      end

      it "validates arguments is a Hash" do
        execution = FunctionExecution.new(valid_attributes.merge(arguments: "not a hash"))
        expect(execution).not_to be_valid
        expect(execution.errors[:arguments]).to include("must be a Hash")
      end

      it "validates result is JSON-serializable" do
        # This should pass - normal hash
        execution = FunctionExecution.new(valid_attributes.merge(result: { "key" => "value" }))
        expect(execution).to be_valid
      end

      it "validates success is boolean" do
        execution = FunctionExecution.new(valid_attributes.merge(success: nil))
        expect(execution).not_to be_valid
        expect(execution.errors[:success]).to include("is not included in the list")
      end
    end

    # Association Tests

    describe "associations" do
      let(:execution) { FunctionExecution.create!(valid_attributes) }

      it "belongs to function_definition" do
        expect(execution.function_definition).to eq(function_definition)
      end
    end

    # Scope Tests

    describe "scopes" do
      before do
        FunctionExecution.create!(valid_attributes.merge(success: true))
        FunctionExecution.create!(valid_attributes.merge(success: false, error_message: "Test error"))
        FunctionExecution.create!(valid_attributes.merge(executed_at: 2.days.ago))
        FunctionExecution.create!(valid_attributes.merge(execution_time_ms: 2000))
      end

      it "filters successful executions" do
        results = FunctionExecution.successful
        expect(results.count).to eq(3)
        expect(results.all?(&:success)).to be true
      end

      it "filters failed executions" do
        results = FunctionExecution.failed
        expect(results.count).to eq(1)
        expect(results.first.success).to be false
      end

      it "filters recent executions" do
        results = FunctionExecution.recent
        expect(results.count).to eq(3)
      end

      it "filters slow executions" do
        results = FunctionExecution.slow(1000)
        expect(results.count).to eq(1)
        expect(results.first.execution_time_ms).to eq(2000)
      end

      it "filters by function" do
        other_function = FunctionDefinition.create!(
          name: "other_function",
          description: "Another function",
          code: "def execute\nend",
          parameters: { "type" => "object" },
          language: "ruby"
        )
        FunctionExecution.create!(valid_attributes.merge(function_definition: other_function))

        results = FunctionExecution.for_function(function_definition.id)
        expect(results.count).to eq(4)
      end
    end

    # Class Method Tests

    describe ".success_rate" do
      it "returns 0 when no executions" do
        expect(FunctionExecution.success_rate).to eq(0.0)
      end

      it "calculates success rate correctly" do
        FunctionExecution.create!(valid_attributes.merge(success: true))
        FunctionExecution.create!(valid_attributes.merge(success: true))
        FunctionExecution.create!(valid_attributes.merge(success: false))

        expect(FunctionExecution.success_rate).to eq(66.67)
      end

      it "returns 100 when all successful" do
        FunctionExecution.create!(valid_attributes.merge(success: true))
        FunctionExecution.create!(valid_attributes.merge(success: true))

        expect(FunctionExecution.success_rate).to eq(100.0)
      end
    end

    describe ".average_execution_time" do
      it "returns 0 when no executions" do
        expect(FunctionExecution.average_execution_time).to eq(0.0)
      end

      it "calculates average execution time correctly" do
        FunctionExecution.create!(valid_attributes.merge(execution_time_ms: 100))
        FunctionExecution.create!(valid_attributes.merge(execution_time_ms: 200))
        FunctionExecution.create!(valid_attributes.merge(execution_time_ms: 300))

        expect(FunctionExecution.average_execution_time).to eq(200.0)
      end
    end
  end
end
