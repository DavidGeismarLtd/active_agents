# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe FunctionDefinition, type: :model do
    # Setup
    let(:valid_code) do
      <<~RUBY
        def execute(city:, units: "celsius")
          api_key = env['OPENWEATHER_API_KEY']
          { temperature: 15, city: city, units: units }
        end
      RUBY
    end

    let(:valid_parameters) do
      {
        "type" => "object",
        "properties" => {
          "city" => { "type" => "string", "description" => "City name" },
          "units" => { "type" => "string", "enum" => [ "celsius", "fahrenheit" ] }
        },
        "required" => [ "city" ]
      }
    end

    let(:valid_attributes) do
      {
        name: "get_weather",
        description: "Get current weather for a city",
        code: valid_code,
        parameters: valid_parameters,
        language: "ruby",
        category: "api",
        tags: [ "weather", "api" ],
        environment_variables: { "OPENWEATHER_API_KEY" => "sk_test_123" },
        dependencies: [ { "name" => "http", "version" => "~> 5.0" } ]
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        function = FunctionDefinition.new(valid_attributes)
        expect(function).to be_valid
      end

      it "requires name" do
        function = FunctionDefinition.new(valid_attributes.except(:name))
        expect(function).not_to be_valid
        expect(function.errors[:name]).to include("can't be blank")
      end

      it "requires unique name" do
        FunctionDefinition.create!(valid_attributes)
        duplicate = FunctionDefinition.new(valid_attributes)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end

      it "requires code" do
        function = FunctionDefinition.new(valid_attributes.except(:code))
        expect(function).not_to be_valid
        expect(function.errors[:code]).to include("can't be blank")
      end

      it "defaults language to ruby" do
        function = FunctionDefinition.new(valid_attributes.except(:language))
        expect(function).to be_valid
        expect(function.language).to eq("ruby")
      end

      it "validates language is in allowed list" do
        function = FunctionDefinition.new(valid_attributes.merge(language: "python"))
        expect(function).not_to be_valid
        expect(function.errors[:language]).to include("is not included in the list")
      end

      it "requires parameters" do
        function = FunctionDefinition.new(valid_attributes.except(:parameters))
        expect(function).not_to be_valid
        expect(function.errors[:parameters]).to include("can't be blank")
      end

      it "validates parameters is a Hash" do
        function = FunctionDefinition.new(valid_attributes.merge(parameters: "not a hash"))
        expect(function).not_to be_valid
        expect(function.errors[:parameters]).to include("must be a valid JSON object")
      end

      it "validates parameters has type: object at root" do
        function = FunctionDefinition.new(valid_attributes.merge(parameters: { "type" => "string" }))
        expect(function).not_to be_valid
        expect(function.errors[:parameters]).to include("must have type: 'object' at root level")
      end

      it "validates code is valid Ruby syntax" do
        invalid_code = "def execute\n  invalid ruby syntax ]["
        function = FunctionDefinition.new(valid_attributes.merge(code: invalid_code))
        expect(function).not_to be_valid
        expect(function.errors[:code]).to be_present
        expect(function.errors[:code].first).to include("contains syntax errors")
      end

      it "accepts valid Ruby code" do
        function = FunctionDefinition.new(valid_attributes)
        expect(function).to be_valid
      end
    end

    # Association Tests

    describe "associations" do
      let(:function) { FunctionDefinition.create!(valid_attributes) }

      it "has many function_executions" do
        expect(function).to respond_to(:function_executions)
        expect(function.function_executions.count).to eq(0)
      end

      it "destroys associated function_executions when destroyed" do
        function.function_executions.create!(
          arguments: { city: "Berlin" },
          result: { temperature: 15 },
          success: true,
          execution_time_ms: 100,
          executed_at: Time.current
        )

        expect { function.destroy }.to change { FunctionExecution.count }.by(-1)
      end
    end

    # Encryption Tests

    describe "encryption" do
      it "encrypts environment_variables" do
        function = FunctionDefinition.create!(valid_attributes)

        # The encrypted value in the database should be different from the plaintext
        raw_value = function.class.connection.select_value(
          "SELECT environment_variables FROM prompt_tracker_function_definitions WHERE id = #{function.id}"
        )

        expect(raw_value).not_to eq(valid_attributes[:environment_variables].to_json)
        expect(function.environment_variables).to eq(valid_attributes[:environment_variables])
      end
    end

    # Scope Tests

    describe "scopes" do
      before do
        FunctionDefinition.create!(valid_attributes.merge(name: "weather_1", category: "api"))
        FunctionDefinition.create!(valid_attributes.merge(name: "weather_2", category: "database", language: "ruby"))
      end

      it "filters by category" do
        results = FunctionDefinition.by_category("api")
        expect(results.count).to eq(1)
        expect(results.first.name).to eq("weather_1")
      end

      it "filters by language" do
        results = FunctionDefinition.by_language("ruby")
        expect(results.count).to eq(2)
      end

      it "searches by name or description" do
        results = FunctionDefinition.search("weather")
        expect(results.count).to eq(2)
      end

      it "returns recently executed functions" do
        func1 = FunctionDefinition.create!(valid_attributes.merge(name: "func1", last_executed_at: 1.hour.ago))
        func2 = FunctionDefinition.create!(valid_attributes.merge(name: "func2", last_executed_at: 2.hours.ago))

        results = FunctionDefinition.recently_executed
        expect(results.first).to eq(func1)
        expect(results.second).to eq(func2)
      end

      it "returns most used functions" do
        func1 = FunctionDefinition.create!(valid_attributes.merge(name: "func1", execution_count: 10))
        func2 = FunctionDefinition.create!(valid_attributes.merge(name: "func2", execution_count: 5))

        results = FunctionDefinition.most_used
        expect(results.first).to eq(func1)
        expect(results.second).to eq(func2)
      end
    end

    # Method Tests

    describe "#test" do
      let(:function) { create(:function_definition, :deployed) }
      let(:mock_result) do
        CodeExecutor::Result.new(
          success?: true,
          result: { temperature: 15, city: "Berlin", units: "celsius" },
          error: nil,
          execution_time_ms: 123,
          logs: ""
        )
      end

      before do
        allow(CodeExecutor).to receive(:execute).and_return(mock_result)
      end

      it "returns a mock response" do
        result = function.test(city: "Berlin")

        expect(result[:success?]).to be true
        expect(result[:result]).to be_present
        expect(result[:error]).to be_nil
        expect(result[:execution_time_ms]).to eq(123)
      end

      it "does not create a function_execution record" do
        expect {
          function.test(city: "Berlin")
        }.not_to change { FunctionExecution.count }
      end
    end

    describe "#execute" do
      let(:function) { create(:function_definition, :deployed) }
      let(:mock_result) do
        CodeExecutor::Result.new(
          success?: true,
          result: { temperature: 15, city: "Berlin", units: "celsius" },
          error: nil,
          execution_time_ms: 123,
          logs: ""
        )
      end

      before do
        allow(CodeExecutor).to receive(:execute).and_return(mock_result)
      end

      it "creates a function_execution record" do
        expect {
          function.execute(city: "Berlin")
        }.to change { FunctionExecution.count }.by(1)
      end

      it "increments execution_count" do
        expect {
          function.execute(city: "Berlin")
        }.to change { function.reload.execution_count }.by(1)
      end

      it "updates last_executed_at" do
        function.execute(city: "Berlin")
        expect(function.reload.last_executed_at).to be_within(1.second).of(Time.current)
      end

      it "updates average_execution_time_ms" do
        function.execute(city: "Berlin")
        expect(function.reload.average_execution_time_ms).to be_present
      end

      it "returns execution result" do
        result = function.execute(city: "Berlin")

        expect(result[:success?]).to be true
        expect(result[:result]).to be_present
      end
    end

    # Environment Variables Tests

    describe "environment variables" do
      describe "associations" do
        it "has many shared_environment_variables through join table" do
          function = FunctionDefinition.create!(valid_attributes)
          env_var = create(:environment_variable, key: "TEST_KEY", value: "test_value")

          function.shared_environment_variables << env_var

          expect(function.shared_environment_variables).to include(env_var)
          expect(env_var.function_definitions).to include(function)
        end
      end

      describe "#merged_environment_variables" do
        it "returns empty hash when no variables are set" do
          function = FunctionDefinition.create!(valid_attributes.merge(environment_variables: nil))
          expect(function.merged_environment_variables).to eq({})
        end

        it "returns inline variables when no shared variables" do
          function = FunctionDefinition.create!(valid_attributes)
          expect(function.merged_environment_variables).to eq({ "OPENWEATHER_API_KEY" => "sk_test_123" })
        end

        it "returns shared variables when no inline variables" do
          function = FunctionDefinition.create!(valid_attributes.merge(environment_variables: nil))
          env_var = create(:environment_variable, key: "SHARED_KEY", value: "shared_value")
          function.shared_environment_variables << env_var

          expect(function.merged_environment_variables).to eq({ "SHARED_KEY" => "shared_value" })
        end

        it "merges shared and inline variables" do
          function = FunctionDefinition.create!(valid_attributes)
          env_var = create(:environment_variable, key: "SHARED_KEY", value: "shared_value")
          function.shared_environment_variables << env_var

          merged = function.merged_environment_variables
          expect(merged["OPENWEATHER_API_KEY"]).to eq("sk_test_123")
          expect(merged["SHARED_KEY"]).to eq("shared_value")
        end

        it "inline variables override shared variables with same key" do
          function = FunctionDefinition.create!(valid_attributes)
          env_var = create(:environment_variable, key: "OPENWEATHER_API_KEY", value: "shared_key_value")
          function.shared_environment_variables << env_var

          # Inline should override shared
          expect(function.merged_environment_variables["OPENWEATHER_API_KEY"]).to eq("sk_test_123")
        end
      end
    end
  end
end
