# frozen_string_literal: true

module PromptTracker
  module Evaluators
    class ConversationJudgeEvaluator < BaseEvaluator
      DEFAULT_CONFIG = {
        judge_model: "gpt-4o",
        evaluation_prompt: "Evaluate this assistant message for quality and appropriateness. Score 0-100.",
        threshold_score: 70
      }.freeze

      def self.param_schema
        {
          judge_model: { type: :string },
          evaluation_prompt: { type: :string },
          threshold_score: { type: :integer }
        }
      end

      def self.metadata
        {
          name: "Conversation Judge",
          description: "Uses an LLM to evaluate each assistant message in a conversation",
          icon: "comments",
          default_config: DEFAULT_CONFIG,
          category: :conversation
        }
      end

      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      def evaluate_score
        scores = message_scores_data.map { |ms| ms[:score] }
        (scores.sum.to_f / scores.length).round(2)
      end

      def generate_feedback
        scores = message_scores_data.map { |ms| ms[:score] }
        average = evaluate_score
        feedback_parts = [
          "Conversation evaluation complete.",
          "Average score: #{average}/100 across #{scores.length} assistant messages.",
          "Individual message scores: #{scores.join(', ')}"
        ]
        if average >= (config[:threshold_score] || 70)
          feedback_parts << "Conversation meets quality threshold."
        else
          feedback_parts << "Conversation below quality threshold."
        end
        feedback_parts.join("\n")
      end

      def metadata
        super.merge(
          "message_scores" => message_scores_data,
          "total_messages" => assistant_messages.length,
          "threshold" => config[:threshold_score] || 70,
          "judge_model" => config[:judge_model]
        )
      end

      def passed?
        threshold = config[:threshold_score] || 70
        evaluate_score >= threshold
      end

      private

      def message_scores_data
        @message_scores_data ||= begin
          raise ArgumentError, "conversation_data must have messages array" if messages.blank?
          raise ArgumentError, "No assistant messages found in conversation" if assistant_messages.empty?
          assistant_messages.map.with_index do |message, index|
            score_message(message, index, messages)
          end
        end
      end

      def score_message(message, index, all_messages)
        context_messages = all_messages[0..index]
        judge_prompt = build_judge_prompt(message, context_messages)
        judge_response = call_llm_judge(judge_prompt)
        score = parse_score_from_response(judge_response)
        {
          message_index: index,
          turn: message["turn"] || message[:turn],
          score: score,
          feedback: judge_response,
          content_preview: (message["content"] || message[:content])[0..100]
        }
      end

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

      def call_llm_judge(judge_prompt)
        return generate_mock_judge_response if use_mock_mode?
        LlmClients::RubyLlmService.with_dynamic_config do |llm|
          chat = llm.chat(model: config[:judge_model])
          response = chat.ask(judge_prompt)
          response.content
        end
      end

      def parse_score_from_response(response)
        if response =~ /Score:\s*(\d+(?:\.\d+)?)/i
          score = ::Regexp.last_match(1).to_f
          return score.clamp(0, 100)
        end
        numbers = response.scan(/\b(\d+(?:\.\d+)?)\b/).flatten.map(&:to_f)
        valid_scores = numbers.select { |n| n >= 0 && n <= 100 }
        return valid_scores.first if valid_scores.any?
        50.0
      end

      def use_mock_mode?
        ENV["PROMPT_TRACKER_USE_REAL_LLM"] != "true"
      end

      def generate_mock_judge_response
        score = rand(75..95)
        <<~RESPONSE
          Score: #{score}
          Feedback: This is a mock evaluation.
        RESPONSE
      end
    end
  end
end
