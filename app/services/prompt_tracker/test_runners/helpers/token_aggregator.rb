# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Helpers
      # Aggregates token usage across multiple messages or API responses.
      #
      # This class provides utilities for calculating total token usage
      # from conversation messages or raw API responses, handling both
      # single-turn and multi-turn scenarios.
      #
      # @example Aggregate tokens from messages
      #   aggregator = TokenAggregator.new
      #   tokens = aggregator.aggregate_from_messages(messages)
      #   # => { "prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150 }
      #
      # @example Aggregate tokens from API responses
      #   aggregator = TokenAggregator.new
      #   tokens = aggregator.aggregate_from_responses(responses)
      #   # => { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
      #
      class TokenAggregator
        # Aggregate token usage from conversation messages
        #
        # Sums up usage data from all assistant messages that have usage information.
        # Returns nil if no messages have usage data.
        #
        # @param messages [Array<Hash>] array of messages with "role" and optional "usage"
        # @return [Hash, nil] aggregated token counts with string keys, or nil if no usage data
        def aggregate_from_messages(messages)
          assistant_messages = messages.select { |m| m["role"] == "assistant" && m["usage"] }
          return nil if assistant_messages.empty?

          {
            "prompt_tokens" => sum_tokens(assistant_messages, "usage", :prompt_tokens),
            "completion_tokens" => sum_tokens(assistant_messages, "usage", :completion_tokens),
            "total_tokens" => sum_tokens(assistant_messages, "usage", :total_tokens)
          }
        end

        # Aggregate token usage from raw API responses
        #
        # Sums up usage data from all responses that have usage information.
        # Returns hash with symbol keys (matching API response format).
        #
        # @param responses [Array<Hash>] array of API responses with :usage key
        # @return [Hash] aggregated token counts with symbol keys
        def aggregate_from_responses(responses)
          {
            prompt_tokens: sum_response_tokens(responses, :prompt_tokens),
            completion_tokens: sum_response_tokens(responses, :completion_tokens),
            total_tokens: sum_response_tokens(responses, :total_tokens)
          }
        end

        private

        # Sum a specific token type from messages
        #
        # @param messages [Array<Hash>] messages with usage data
        # @param usage_key [String] key to access usage hash (e.g., "usage")
        # @param token_type [Symbol] type of tokens to sum (e.g., :prompt_tokens)
        # @return [Integer] total tokens
        def sum_tokens(messages, usage_key, token_type)
          messages.sum { |m| m.dig(usage_key, token_type) || 0 }
        end

        # Sum a specific token type from API responses
        #
        # @param responses [Array<Hash>] API responses with :usage key
        # @param token_type [Symbol] type of tokens to sum (e.g., :prompt_tokens)
        # @return [Integer] total tokens
        def sum_response_tokens(responses, token_type)
          responses.sum { |r| r.dig(:usage, token_type) || 0 }
        end
      end
    end
  end
end
