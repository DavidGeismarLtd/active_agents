# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module SingleResponse
      # Base class for evaluators that work with single (normalized) responses.
      #
      # These evaluators receive a normalized response hash and evaluate single-turn responses.
      # The response is API-agnostic - it has been normalized by the appropriate normalizer
      # before being passed to the evaluator.
      #
      # Used for: single_turn test mode on any testable.
      #
      # Subclasses should implement:
      # - #evaluate_score: Calculate the numeric score (0-100)
      # - .metadata: Class method providing evaluator metadata
      # - .compatible_with_apis: (optional) Override to specify API compatibility
      #
      # @example Creating a single-response evaluator
      #   class MyEvaluator < BaseSingleResponseEvaluator
      #     def self.compatible_with_apis
      #       [:all]  # Works with all APIs
      #     end
      #
      #     def evaluate_score
      #       response_text.length > 100 ? 100 : 50
      #     end
      #   end
      #
      class BaseSingleResponseEvaluator < BaseEvaluator
        attr_reader :response

        # Returns the evaluator category
        #
        # @return [Symbol] :single_response
        def self.category
          :single_response
        end

        # Returns the API type (legacy)
        #
        # @return [Symbol] :chat_completion
        def self.api_type
          :chat_completion
        end

        # Returns compatible testable classes (legacy)
        #
        # @return [Array<Class>] array containing PromptVersion
        def self.compatible_with
          [ PromptTracker::PromptVersion ]
        end

        # Initialize the evaluator with a normalized response
        #
        # @param response [String, Hash] the response to evaluate
        #   - String: treated as response text
        #   - Hash: should contain :text, :tool_calls, :metadata
        # @param config [Hash] configuration for the evaluator
        def initialize(response, config = {})
          @response = normalize_response(response)
          super(config)
        end

        # Get the response text
        #
        # @return [String] the response text content
        def response_text
          response[:text] || ""
        end

        # Get tool calls from the response
        #
        # @return [Array<Hash>] array of tool call objects
        def tool_calls
          response[:tool_calls] || []
        end

        # Get response metadata
        #
        # @return [Hash] metadata about the response
        def response_metadata
          response[:metadata] || {}
        end

        # Evaluate and create an Evaluation record
        #
        # @return [Evaluation] the created evaluation
        def evaluate
          score = evaluate_score
          feedback_text = generate_feedback

          Evaluation.create!(
            llm_response: config[:llm_response],
            test_run: config[:test_run],
            evaluator_type: self.class.name,
            evaluator_config_id: config[:evaluator_config_id],
            score: score,
            score_min: 0,
            score_max: 100,
            passed: passed?,
            feedback: feedback_text,
            metadata: metadata,
            evaluation_context: config[:evaluation_context] || "tracked_call"
          )
        end

        private

        # Normalize input to standard response format
        #
        # @param input [String, Hash] raw response input
        # @return [Hash] normalized response with :text, :tool_calls, :metadata
        def normalize_response(input)
          case input
          when String
            { text: input, tool_calls: [], metadata: {} }
          when Hash
            {
              text: input[:text] || input["text"] || "",
              tool_calls: input[:tool_calls] || input["tool_calls"] || [],
              metadata: input[:metadata] || input["metadata"] || {}
            }
          else
            { text: input.to_s, tool_calls: [], metadata: {} }
          end
        end
      end
    end
  end
end
