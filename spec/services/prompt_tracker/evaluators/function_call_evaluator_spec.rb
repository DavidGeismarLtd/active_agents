# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe FunctionCallEvaluator, type: :service do
      let(:conversation_data_with_tool_calls) do
        {
          "messages" => [
            { "role" => "user", "content" => "What's the weather in London?", "turn" => 1 },
            {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                {
                  "id" => "call_abc123",
                  "type" => "function",
                  "function" => {
                    "name" => "get_weather",
                    "arguments" => '{"location": "London"}'
                  }
                }
              ],
              "turn" => 1
            },
            { "role" => "assistant", "content" => "The weather in London is sunny.", "turn" => 1 }
          ]
        }
      end

      let(:conversation_data_no_tool_calls) do
        {
          "messages" => [
            { "role" => "user", "content" => "Hello", "turn" => 1 },
            { "role" => "assistant", "content" => "Hi there!", "turn" => 1 }
          ]
        }
      end

      let(:conversation_data_multiple_tool_calls) do
        {
          "messages" => [
            { "role" => "user", "content" => "Plan my trip", "turn" => 1 },
            {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                { "id" => "call_1", "type" => "function", "function" => { "name" => "get_weather", "arguments" => "{}" } },
                { "id" => "call_2", "type" => "function", "function" => { "name" => "book_flight", "arguments" => "{}" } }
              ],
              "turn" => 1
            },
            { "role" => "assistant", "content" => "I've checked weather and booked flight.", "turn" => 1 }
          ]
        }
      end

      describe ".metadata" do
        it "returns evaluator metadata" do
          metadata = described_class.metadata

          expect(metadata[:name]).to eq("Function Call")
          expect(metadata[:description]).to include("function")
          expect(metadata[:icon]).to eq("gear")
          expect(metadata[:category]).to eq(:conversation)
        end
      end

      describe ".param_schema" do
        it "returns parameter schema" do
          schema = described_class.param_schema

          expect(schema).to have_key(:expected_functions)
          expect(schema).to have_key(:require_all)
          expect(schema).to have_key(:check_arguments)
          expect(schema).to have_key(:threshold_score)
        end
      end

      describe "#evaluate_score" do
        context "when no expected functions specified" do
          it "returns 100" do
            evaluator = described_class.new(conversation_data_with_tool_calls, { expected_functions: [] })
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "with require_all: true" do
          it "returns 100 when all expected functions are called" do
            evaluator = described_class.new(conversation_data_with_tool_calls, {
              expected_functions: [ "get_weather" ],
              require_all: true
            })
            expect(evaluator.evaluate_score).to eq(100)
          end

          it "returns partial score when some functions are missing" do
            evaluator = described_class.new(conversation_data_with_tool_calls, {
              expected_functions: [ "get_weather", "get_forecast" ],
              require_all: true
            })
            expect(evaluator.evaluate_score).to eq(50) # 1 of 2 = 50%
          end

          it "returns 0 when no expected functions are called" do
            evaluator = described_class.new(conversation_data_no_tool_calls, {
              expected_functions: [ "get_weather" ],
              require_all: true
            })
            expect(evaluator.evaluate_score).to eq(0)
          end
        end

        context "with require_all: false" do
          it "returns 100 when any expected function is called" do
            evaluator = described_class.new(conversation_data_with_tool_calls, {
              expected_functions: [ "get_weather", "get_forecast" ],
              require_all: false
            })
            expect(evaluator.evaluate_score).to eq(100)
          end

          it "returns 0 when no expected functions are called" do
            evaluator = described_class.new(conversation_data_no_tool_calls, {
              expected_functions: [ "get_weather" ],
              require_all: false
            })
            expect(evaluator.evaluate_score).to eq(0)
          end
        end
      end

      describe "#generate_feedback" do
        it "describes success when all functions called" do
          evaluator = described_class.new(conversation_data_with_tool_calls, {
            expected_functions: [ "get_weather" ],
            require_all: true
          })
          feedback = evaluator.generate_feedback

          expect(feedback).to include("✓")
          expect(feedback).to include("get_weather")
        end

        it "describes missing functions" do
          evaluator = described_class.new(conversation_data_with_tool_calls, {
            expected_functions: [ "get_weather", "get_forecast" ],
            require_all: true
          })
          feedback = evaluator.generate_feedback

          expect(feedback).to include("✗")
          expect(feedback).to include("get_forecast")
        end
      end

      describe "#passed?" do
        it "returns true when score meets threshold" do
          evaluator = described_class.new(conversation_data_with_tool_calls, {
            expected_functions: [ "get_weather" ],
            threshold_score: 80
          })
          expect(evaluator.passed?).to be true
        end

        it "returns false when score below threshold" do
          evaluator = described_class.new(conversation_data_no_tool_calls, {
            expected_functions: [ "get_weather" ],
            threshold_score: 80
          })
          expect(evaluator.passed?).to be false
        end
      end

      describe "argument checking" do
        let(:conversation_with_flight_search) do
          {
            "messages" => [
              { "role" => "user", "content" => "Find flights from JFK to LHR", "turn" => 1 },
              {
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_flight_1",
                    "type" => "function",
                    "function" => {
                      "name" => "search_flights",
                      "arguments" => '{"origin": "JFK", "destination": "LHR", "date": "2024-06-15"}'
                    }
                  }
                ],
                "turn" => 1
              },
              { "role" => "assistant", "content" => "Found flights from JFK to LHR.", "turn" => 1 }
            ]
          }
        end

        let(:conversation_with_nested_args) do
          {
            "messages" => [
              { "role" => "user", "content" => "Create an order", "turn" => 1 },
              {
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_order_1",
                    "type" => "function",
                    "function" => {
                      "name" => "create_order",
                      "arguments" => '{"customer": {"name": "John", "email": "john@example.com"}, "items": ["item1"]}'
                    }
                  }
                ],
                "turn" => 1
              }
            ]
          }
        end

        context "with check_arguments: true" do
          it "returns 100 when arguments match expected values" do
            evaluator = described_class.new(conversation_with_flight_search, {
              expected_functions: [ "search_flights" ],
              require_all: true,
              check_arguments: true,
              expected_arguments: {
                "search_flights" => { "origin" => "JFK", "destination" => "LHR" }
              }
            })
            expect(evaluator.evaluate_score).to eq(100)
          end

          it "returns reduced score when arguments don't match" do
            evaluator = described_class.new(conversation_with_flight_search, {
              expected_functions: [ "search_flights" ],
              require_all: true,
              check_arguments: true,
              expected_arguments: {
                "search_flights" => { "origin" => "LAX" }  # Expected LAX but got JFK
              }
            })
            expect(evaluator.evaluate_score).to be < 100
          end

          it "matches nested argument structures" do
            evaluator = described_class.new(conversation_with_nested_args, {
              expected_functions: [ "create_order" ],
              require_all: true,
              check_arguments: true,
              expected_arguments: {
                "create_order" => {
                  "customer" => { "name" => "John" }
                }
              }
            })
            expect(evaluator.evaluate_score).to eq(100)
          end

          it "ignores extra arguments in actual call (subset matching)" do
            evaluator = described_class.new(conversation_with_flight_search, {
              expected_functions: [ "search_flights" ],
              require_all: true,
              check_arguments: true,
              expected_arguments: {
                "search_flights" => { "origin" => "JFK" }  # Only checking origin
              }
            })
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "with check_arguments: false" do
          it "ignores argument values" do
            evaluator = described_class.new(conversation_with_flight_search, {
              expected_functions: [ "search_flights" ],
              require_all: true,
              check_arguments: false,
              expected_arguments: {
                "search_flights" => { "origin" => "LAX" }  # Wrong origin, but should be ignored
              }
            })
            expect(evaluator.evaluate_score).to eq(100)
          end
        end
      end

      describe "multiple function calls" do
        let(:conversation_with_travel_planning) do
          {
            "messages" => [
              { "role" => "user", "content" => "Plan my trip to Paris", "turn" => 1 },
              {
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_1",
                    "type" => "function",
                    "function" => {
                      "name" => "search_flights",
                      "arguments" => '{"origin": "JFK", "destination": "CDG"}'
                    }
                  },
                  {
                    "id" => "call_2",
                    "type" => "function",
                    "function" => {
                      "name" => "search_hotels",
                      "arguments" => '{"city": "Paris"}'
                    }
                  },
                  {
                    "id" => "call_3",
                    "type" => "function",
                    "function" => {
                      "name" => "get_weather",
                      "arguments" => '{"location": "Paris"}'
                    }
                  }
                ],
                "turn" => 1
              }
            ]
          }
        end

        it "validates all expected functions with arguments" do
          evaluator = described_class.new(conversation_with_travel_planning, {
            expected_functions: [ "search_flights", "search_hotels", "get_weather" ],
            require_all: true,
            check_arguments: true,
            expected_arguments: {
              "search_flights" => { "destination" => "CDG" },
              "search_hotels" => { "city" => "Paris" },
              "get_weather" => { "location" => "Paris" }
            }
          })
          expect(evaluator.evaluate_score).to eq(100)
        end

        it "generates detailed feedback for multiple functions" do
          evaluator = described_class.new(conversation_with_travel_planning, {
            expected_functions: [ "search_flights", "search_hotels", "book_flight" ],
            require_all: true
          })
          feedback = evaluator.generate_feedback

          expect(feedback).to include("search_flights")
          expect(feedback).to include("search_hotels")
          expect(feedback).to include("book_flight")
        end
      end
    end
  end
end
