# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Openai::Responses::FunctionInputBuilder do
  let(:executor) { PromptTracker::Openai::Responses::FunctionExecutor.new }
  subject(:builder) { described_class.new(executor: executor) }

  let(:tool_calls) do
    [
      {
        id: "call_abc123",
        function_name: "get_weather",
        arguments: { city: "Paris" }
      },
      {
        id: "call_def456",
        function_name: "get_time",
        arguments: { timezone: "UTC" }
      }
    ]
  end

  describe "#build_outputs" do
    it "creates function_call_output items for each tool call" do
      outputs = builder.build_outputs(tool_calls)

      expect(outputs.length).to eq(2)
      expect(outputs[0][:type]).to eq("function_call_output")
      expect(outputs[0][:call_id]).to eq("call_abc123")
      expect(outputs[1][:type]).to eq("function_call_output")
      expect(outputs[1][:call_id]).to eq("call_def456")
    end

    it "executes each function and includes the output" do
      outputs = builder.build_outputs(tool_calls)

      parsed_output_0 = JSON.parse(outputs[0][:output])
      expect(parsed_output_0["message"]).to eq("Mock result for get_weather")

      parsed_output_1 = JSON.parse(outputs[1][:output])
      expect(parsed_output_1["message"]).to eq("Mock result for get_time")
    end

    it "returns empty array for empty tool calls" do
      outputs = builder.build_outputs([])
      expect(outputs).to eq([])
    end
  end

  describe "#pair_calls_with_outputs" do
    let(:function_outputs) do
      [
        { type: "function_call_output", call_id: "call_abc123", output: '{"result": "sunny"}' },
        { type: "function_call_output", call_id: "call_def456", output: '{"time": "14:30"}' }
      ]
    end

    it "interleaves function_call and function_call_output items" do
      paired = builder.pair_calls_with_outputs(tool_calls, function_outputs)

      expect(paired.length).to eq(4)
      expect(paired[0][:type]).to eq("function_call")
      expect(paired[1][:type]).to eq("function_call_output")
      expect(paired[2][:type]).to eq("function_call")
      expect(paired[3][:type]).to eq("function_call_output")
    end

    it "pairs each function_call with its matching output" do
      paired = builder.pair_calls_with_outputs(tool_calls, function_outputs)

      # First pair
      expect(paired[0][:call_id]).to eq("call_abc123")
      expect(paired[0][:name]).to eq("get_weather")
      expect(paired[1][:call_id]).to eq("call_abc123")
      expect(paired[1][:output]).to eq('{"result": "sunny"}')

      # Second pair
      expect(paired[2][:call_id]).to eq("call_def456")
      expect(paired[2][:name]).to eq("get_time")
      expect(paired[3][:call_id]).to eq("call_def456")
      expect(paired[3][:output]).to eq('{"time": "14:30"}')
    end

    it "converts hash arguments to JSON string" do
      paired = builder.pair_calls_with_outputs(tool_calls, function_outputs)

      expect(paired[0][:arguments]).to eq('{"city":"Paris"}')
      expect(paired[2][:arguments]).to eq('{"timezone":"UTC"}')
    end

    it "preserves string arguments as-is" do
      tool_calls[0][:arguments] = '{"already": "json"}'
      paired = builder.pair_calls_with_outputs(tool_calls, function_outputs)

      expect(paired[0][:arguments]).to eq('{"already": "json"}')
    end

    it "returns empty array for empty inputs" do
      paired = builder.pair_calls_with_outputs([], [])
      expect(paired).to eq([])
    end
  end

  describe "#build_continuation_input" do
    it "combines build_outputs and pair_calls_with_outputs" do
      input = builder.build_continuation_input(tool_calls)

      expect(input.length).to eq(4)
      expect(input[0][:type]).to eq("function_call")
      expect(input[1][:type]).to eq("function_call_output")
      expect(input[2][:type]).to eq("function_call")
      expect(input[3][:type]).to eq("function_call_output")
    end

    it "properly pairs calls with their executed outputs" do
      input = builder.build_continuation_input(tool_calls)

      # Verify first pair
      expect(input[0][:call_id]).to eq(input[1][:call_id])
      expect(input[0][:name]).to eq("get_weather")

      # Verify second pair
      expect(input[2][:call_id]).to eq(input[3][:call_id])
      expect(input[2][:name]).to eq("get_time")
    end

    context "with custom executor mocks" do
      let(:mock_outputs) { { "get_weather" => { temp: 25 } } }
      let(:executor) { PromptTracker::Openai::Responses::FunctionExecutor.new(mock_function_outputs: mock_outputs) }

      it "uses the custom mock in outputs" do
        input = builder.build_continuation_input(tool_calls)

        weather_output = JSON.parse(input[1][:output])
        expect(weather_output["temp"]).to eq(25)
      end
    end
  end
end
