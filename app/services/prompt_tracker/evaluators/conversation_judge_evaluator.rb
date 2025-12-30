# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates assistant conversations by scoring each assistant message using an LLM judge.
    #
    # This evaluator:
    # 1. Takes conversation_data (Hash with messages array)
    # 2. For each assistant message, asks an LLM judge to score it
    # 3. Averages the scores across all assistant messages
    # 4. Returns an evaluation with per-message scores in metadata
    #
    # Unlike LlmJudgeEvaluator which evaluates a single LLM response,
    # this evaluator handles multi-turn conversations.
    #
    # @example Evaluate a conversation
    #   evaluator = ConversationJudgeEvaluator.new(conversation_data, {
    #     judge_model: "gpt-4o",
    #     evaluation_prompt: "Evaluate this assistant message for empathy and accuracy. Score 0-100."
    #   })
    #   evaluation = evaluator.evaluate
    #   # => Evaluation with:
    #   #    - score: 85 (average of all message scores)
    #   #    - metadata: { message_scores: [90, 80, 85], ... }
    #
    class ConversationJudgeEvaluator < BaseOpenaiAssistantEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        judge_model: "gpt-4o",
        evaluation_prompt: "Evaluate this assistant message for quality and appropriateness. Score 0-100.",
        threshold_score: 70
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          judge_model: { type: :string },
          evaluation_prompt: { type: :string },
          threshold_score: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Conversation Judge",
          description: "Uses an LLM to evaluate each assistant message in a conversation",
          icon: "comments",
          default_config: DEFAULT_CONFIG,
          category: :conversation
        }
      end

      # Initialize the evaluator
      #
      # @param conversation_data [Hash] the conversation data with messages array
      # @param config [Hash] configuration options
      def initialize(conversation_data, config = {})
        super(conversation_data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      # Calculate score by averaging all assistant message scores
      #
      # @return [Float] average score from 0-100
      def evaluate_score
        scores = message_scores_data.map { |ms| ms[:score] }
        (scores.sum.to_f / scores.length).round(2)
      end

      # Generate feedback summarizing the conversation evaluation
      #
      # @return [String] feedback text
      def generate_feedback
        scores = message_scores_data.map { |ms| ms[:score] }
        average = evaluate_score

        feedback_parts = [
          "Conversation evaluation complete.",
          "Average score: #{average}/100 across #{scores.length} assistant messages.",
          "Individual message scores: #{scores.join(', ')}"
        ]

        if average >= (config[:threshold_score] || 70)
          feedback_parts << "✓ Conversation meets quality threshold."
        else
          feedback_parts << "✗ Conversation below quality threshold."
        end

        feedback_parts.join("\n")
      end

      # Add metadata about message-level scores
      #
      # @return [Hash] metadata
      def metadata
        super.merge(
          "message_scores" => message_scores_data,
          "total_messages" => assistant_messages.length,
          "threshold" => config[:threshold_score] || 70,
          "judge_model" => config[:judge_model]
        )
      end

      # Custom pass/fail logic based on threshold
      #
      # @return [Boolean] true if average score >= threshold
      def passed?
        threshold = config[:threshold_score] || 70
        evaluate_score >= threshold
      end

      private

      # Get messages from conversation_data
      #
      # @return [Array<Hash>] array of messages
      def messages
        raise ArgumentError, "conversation_data must have conversation_data" if conversation_data.nil?

        @messages ||= conversation_data["messages"] || conversation_data[:messages] || []
      end

      # Get assistant messages from conversation
      #
      # @return [Array<Hash>] array of assistant messages
      def assistant_messages
        @assistant_messages ||= messages.select { |m| m["role"] == "assistant" || m[:role] == "assistant" }
      end

      # Get or compute message scores (memoized)
      # This ensures we only call the LLM once per message
      #
      # @return [Array<Hash>] array of message score hashes
      def message_scores_data
        @message_scores_data ||= begin
          raise ArgumentError, "conversation_data must have messages array" if messages.blank?
          raise ArgumentError, "No assistant messages found in conversation" if assistant_messages.empty?

          assistant_messages.map.with_index do |message, index|
            score_message(message, index, messages)
          end
        end
      end

      # Score a single assistant message
      #
      # @param message [Hash] the assistant message
      # @param index [Integer] the message index
      # @param all_messages [Array<Hash>] all messages in the conversation
      # @return [Hash] score and feedback for this message
      def score_message(message, index, all_messages)
        # Build context: include previous messages for context
        context_messages = all_messages[0..index]

        # Build judge prompt
        judge_prompt = build_judge_prompt(message, context_messages)

        # Call LLM judge
        judge_response = call_llm_judge(judge_prompt)

        # Parse score from response
        score = parse_score_from_response(judge_response)

        {
          message_index: index,
          turn: message["turn"] || message[:turn],
          score: score,
          feedback: judge_response,
          content_preview: (message["content"] || message[:content])[0..100]
        }
      end

      # Build the judge prompt for a single message
      #
      # @param message [Hash] the assistant message to evaluate
      # @param context_messages [Array<Hash>] previous messages for context
      # @return [String] the judge prompt
      def build_judge_prompt(message, context_messages)
        conversation_context = context_messages.map do |m|
          role = m["role"] || m[:role]
          content = m["content"] || m[:content]
          "#{role.upcase}: #{content}"
        end.join("\n\n")

        <<~PROMPT
          #{config[:evaluation_prompt]}

          CONVERSATION CONTEXT:
          #{conversation_context}

          Please provide:
          1. A score from 0-100
          2. Brief feedback explaining the score

          Format your response as:
          Score: [number]
          Feedback: [your feedback]
        PROMPT
      end

      # Call the LLM judge
      #
      # @param judge_prompt [String] the prompt for the judge
      # @return [String] the judge's response
      def call_llm_judge(judge_prompt)
        # Check if we should use mock mode
        if use_mock_mode?
          return generate_mock_judge_response
        end

        # Use RubyLLM to call the judge model
        chat = RubyLLM.chat(model: config[:judge_model])
        response = chat.ask(judge_prompt)
        response.content
        # rescue => e
        #   Rails.logger.error("ConversationJudgeEvaluator failed: #{e.message}")
        #   "Score: 50\nFeedback: Error during evaluation: #{e.message}"
      end

      # Parse score from judge response
      #
      # @param response [String] the judge's response
      # @return [Float] the extracted score (0-100)
      def parse_score_from_response(response)
        # Try to extract score from "Score: XX" format
        if response =~ /Score:\s*(\d+(?:\.\d+)?)/i
          score = ::Regexp.last_match(1).to_f
          return score.clamp(0, 100)
        end

        # Try to extract any number between 0-100
        numbers = response.scan(/\b(\d+(?:\.\d+)?)\b/).flatten.map(&:to_f)
        valid_scores = numbers.select { |n| n >= 0 && n <= 100 }
        return valid_scores.first if valid_scores.any?

        # Default to 50 if we can't parse
        50.0
      end



      # Check if we should use mock mode
      #
      # @return [Boolean] true if using mock responses
      def use_mock_mode?
        ENV["PROMPT_TRACKER_USE_REAL_LLM"] != "true"
      end

      # Generate a mock judge response for testing
      #
      # @return [String] mock judge response
      def generate_mock_judge_response
        score = rand(75..95)
        <<~RESPONSE
          Score: #{score}
          Feedback: This is a mock evaluation. The assistant message demonstrates good quality and appropriateness.
        RESPONSE
      end
    end
  end
end
