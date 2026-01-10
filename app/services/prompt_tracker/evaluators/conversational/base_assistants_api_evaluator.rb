# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Conversational
      # Base class for evaluators that require Assistants API-specific data.
      #
      # Extends BaseConversationalEvaluator with access to run_steps, threads, etc.
      # These evaluators only work with OpenAI Assistants (not Response API).
      #
      # Used for: Assistants only (requires run_steps, threads, file_search results, etc.)
      #
      # Subclasses should implement:
      # - #evaluate_score: Calculate the numeric score (0-100)
      # - .metadata: Class method providing evaluator metadata
      #
      # @example Creating an Assistants-specific evaluator
      #   class MyAssistantEvaluator < BaseAssistantsApiEvaluator
      #     def evaluate_score
      #       run_steps_available? ? 100 : 0
      #     end
      #   end
      #
      class BaseAssistantsApiEvaluator < BaseConversationalEvaluator
        # Returns the API type this evaluator works with
        #
        # @return [Symbol] :assistants_api
        def self.api_type
          :assistants_api
        end

        # Returns compatible API types
        #
        # @return [Array<Symbol>] array containing only Assistants API
        def self.compatible_with_apis
          [ ApiTypes::OPENAI_ASSISTANTS_API ]
        end

        # Returns compatible testable classes (legacy)
        # Assistants API evaluators only work with OpenAI Assistants
        #
        # @return [Array<Class>] array containing Openai::Assistant
        def self.compatible_with
          [ PromptTracker::Openai::Assistant ]
        end

        # Helper: Get run_steps from conversation data
        #
        # @return [Array<Hash>] array of run_step hashes
        def run_steps
          @run_steps ||= conversation[:run_steps] || conversation_data["run_steps"] || conversation_data[:run_steps] || []
        end

        # Helper: Check if run_steps are available
        #
        # @return [Boolean] true if run_steps data is present
        def run_steps_available?
          run_steps.any?
        end

        # Helper: Get file_search results from run_steps
        #
        # @return [Array<Hash>] array of file_search step details
        def file_search_steps
          @file_search_steps ||= run_steps.select do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            step_details["type"] == "tool_calls" || step_details[:type] == "tool_calls"
          end.flat_map do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []
            tool_calls.select do |tc|
              tc["type"] == "file_search" || tc[:type] == "file_search"
            end
          end
        end

        # Helper: Get code_interpreter results from run_steps
        #
        # @return [Array<Hash>] array of code_interpreter step details
        def code_interpreter_steps
          @code_interpreter_steps ||= run_steps.select do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            step_details["type"] == "tool_calls" || step_details[:type] == "tool_calls"
          end.flat_map do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []
            tool_calls.select do |tc|
              tc["type"] == "code_interpreter" || tc[:type] == "code_interpreter"
            end
          end
        end
      end
    end
  end
end
