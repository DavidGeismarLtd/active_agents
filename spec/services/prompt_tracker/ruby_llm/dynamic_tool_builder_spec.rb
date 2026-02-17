# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::RubyLlm::DynamicToolBuilder do
  describe ".build" do
    let(:tool_config) do
      {
        "functions" => [
          {
            "name" => "get_weather",
            "description" => "Get weather for a city",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string", "description" => "City name" },
                "units" => { "type" => "string", "description" => "Temperature units" }
              },
              "required" => [ "city" ]
            }
          }
        ]
      }
    end

    it "creates RubyLLM::Tool subclasses" do
      tools = described_class.build(tool_config: tool_config)

      expect(tools.length).to eq(1)
      expect(tools.first.superclass).to eq(RubyLLM::Tool)
    end

    it "sets tool name correctly via instance method" do
      tools = described_class.build(tool_config: tool_config)
      tool_instance = tools.first.new

      expect(tool_instance.name).to eq("get_weather")
    end

    it "sets tool name correctly via class method" do
      tools = described_class.build(tool_config: tool_config)

      expect(tools.first.tool_name).to eq("get_weather")
    end

    it "sets description on the tool class" do
      tools = described_class.build(tool_config: tool_config)

      expect(tools.first.description).to eq("Get weather for a city")
    end

    it "returns default mock data on execute" do
      tools = described_class.build(tool_config: tool_config)
      tool_instance = tools.first.new

      result = tool_instance.execute(city: "Berlin", units: "celsius")

      expect(result[:status]).to eq("success")
      expect(result[:function]).to eq("get_weather")
      expect(result[:result]).to eq("Mock response for get_weather")
      expect(result[:received_arguments]).to eq({ city: "Berlin", units: "celsius" })
    end

    context "with multiple functions" do
      let(:tool_config) do
        {
          "functions" => [
            { "name" => "get_weather", "description" => "Get weather" },
            { "name" => "get_stock_price", "description" => "Get stock price" },
            { "name" => "send_email", "description" => "Send an email" }
          ]
        }
      end

      it "creates a tool class for each function" do
        tools = described_class.build(tool_config: tool_config)

        expect(tools.length).to eq(3)
        expect(tools.map { |t| t.new.name }).to eq([ "get_weather", "get_stock_price", "send_email" ])
      end
    end

    context "with custom mock outputs" do
      let(:mock_outputs) do
        {
          "get_weather" => { "temperature" => 72, "conditions" => "Sunny" }
        }
      end

      it "returns custom mock output as hash" do
        tools = described_class.build(
          tool_config: tool_config,
          mock_function_outputs: mock_outputs
        )
        tool_instance = tools.first.new

        result = tool_instance.execute(city: "Berlin")

        expect(result).to eq({ "temperature" => 72, "conditions" => "Sunny" })
      end

      context "when mock output is a string" do
        let(:mock_outputs) { { "get_weather" => "Weather data unavailable" } }

        it "wraps non-hash mock in result key" do
          tools = described_class.build(
            tool_config: tool_config,
            mock_function_outputs: mock_outputs
          )
          tool_instance = tools.first.new

          result = tool_instance.execute(city: "Berlin")

          expect(result).to eq({ result: "Weather data unavailable" })
        end
      end
    end

    context "with empty tool config" do
      let(:tool_config) { {} }

      it "returns empty array" do
        tools = described_class.build(tool_config: tool_config)

        expect(tools).to eq([])
      end
    end

    context "with nil tool config" do
      it "returns empty array" do
        tools = described_class.build(tool_config: nil)

        expect(tools).to eq([])
      end
    end

    context "with function without parameters" do
      let(:tool_config) do
        {
          "functions" => [
            { "name" => "get_time", "description" => "Get current time" }
          ]
        }
      end

      it "creates tool without errors" do
        tools = described_class.build(tool_config: tool_config)
        tool_instance = tools.first.new

        result = tool_instance.execute

        expect(result[:function]).to eq("get_time")
      end
    end

    context "with function without description" do
      let(:tool_config) do
        {
          "functions" => [ { "name" => "do_something" } ]
        }
      end

      it "uses empty string for description" do
        tools = described_class.build(tool_config: tool_config)

        expect(tools.first.description).to eq("")
      end
    end
  end
end
