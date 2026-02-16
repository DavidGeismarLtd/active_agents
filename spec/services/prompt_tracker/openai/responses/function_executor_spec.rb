# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Openai::Responses::FunctionExecutor do
  describe "#execute" do
    let(:tool_call) do
      {
        id: "call_abc123",
        function_name: "get_weather",
        arguments: { city: "Paris", units: "celsius" }
      }
    end

    context "when no custom mock is configured" do
      subject(:executor) { described_class.new }

      it "returns a default mock response" do
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["success"]).to be true
        expect(parsed["message"]).to eq("Mock result for get_weather")
        expect(parsed["data"]).to eq({ "city" => "Paris", "units" => "celsius" })
      end

      it "includes the function name in the response message" do
        tool_call[:function_name] = "search_database"
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["message"]).to eq("Mock result for search_database")
      end

      it "handles string arguments" do
        tool_call[:arguments] = '{"location": "Tokyo"}'
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["data"]).to eq('{"location": "Tokyo"}')
      end
    end

    context "when custom mock is configured as a Hash" do
      let(:mock_function_outputs) do
        {
          "get_weather" => { temperature: 22, condition: "sunny", humidity: 45 }
        }
      end

      subject(:executor) { described_class.new(mock_function_outputs: mock_function_outputs) }

      it "returns the custom mock response as JSON" do
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["temperature"]).to eq(22)
        expect(parsed["condition"]).to eq("sunny")
        expect(parsed["humidity"]).to eq(45)
      end

      it "falls back to default mock for unconfigured functions" do
        tool_call[:function_name] = "get_time"
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["success"]).to be true
        expect(parsed["message"]).to eq("Mock result for get_time")
      end
    end

    context "when custom mock is configured as a String" do
      let(:mock_function_outputs) do
        {
          "get_weather" => '{"raw": "pre-formatted JSON response"}'
        }
      end

      subject(:executor) { described_class.new(mock_function_outputs: mock_function_outputs) }

      it "returns the string as-is" do
        result = executor.execute(tool_call)

        expect(result).to eq('{"raw": "pre-formatted JSON response"}')
      end
    end

    context "with multiple custom mocks" do
      let(:mock_function_outputs) do
        {
          "get_weather" => { temp: 20 },
          "get_time" => { time: "14:30" },
          "search_database" => { results: [] }
        }
      end

      subject(:executor) { described_class.new(mock_function_outputs: mock_function_outputs) }

      it "returns the correct mock for each function" do
        weather_result = executor.execute(tool_call)
        expect(JSON.parse(weather_result)["temp"]).to eq(20)

        tool_call[:function_name] = "get_time"
        time_result = executor.execute(tool_call)
        expect(JSON.parse(time_result)["time"]).to eq("14:30")

        tool_call[:function_name] = "search_database"
        search_result = executor.execute(tool_call)
        expect(JSON.parse(search_result)["results"]).to eq([])
      end
    end

    context "when mock_function_outputs is an empty hash" do
      subject(:executor) { described_class.new(mock_function_outputs: {}) }

      it "falls back to default mock" do
        result = executor.execute(tool_call)
        parsed = JSON.parse(result)

        expect(parsed["success"]).to be true
        expect(parsed["message"]).to eq("Mock result for get_weather")
      end
    end
  end
end
