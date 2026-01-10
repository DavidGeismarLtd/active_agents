# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates response based on presence of required/forbidden keywords.
    #
    # Scores responses based on whether they contain required keywords
    # and avoid forbidden keywords.
    #
    # @example Evaluate with required keywords
    #   evaluator = KeywordEvaluator.new(response_text, {
    #     required_keywords: ["hello", "welcome"],
    #     forbidden_keywords: ["error", "failed"]
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Case-insensitive matching
    #   evaluator = KeywordEvaluator.new(response_text, {
    #     required_keywords: ["Hello"],
    #     case_sensitive: false
    #   })
    #
    class KeywordEvaluator < SingleResponse::BaseSingleResponseEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        required_keywords: [],   # Keywords that must be present
        forbidden_keywords: [],  # Keywords that must not be present
        case_sensitive: false    # Whether to match case-sensitively
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          required_keywords: { type: :array },
          forbidden_keywords: { type: :array },
          case_sensitive: { type: :boolean }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Keyword Checker",
          description: "Checks for required and forbidden keywords in the response",
          icon: "search",
          default_config: DEFAULT_CONFIG
        }
      end

      def initialize(response_text, config = {})
        super(response_text, DEFAULT_CONFIG.merge(config.deep_symbolize_keys))
      end

      def evaluate_score
        required = config[:required_keywords] || []
        forbidden = config[:forbidden_keywords] || []

        # If no keywords configured, return perfect score
        return 100 if required.empty? && forbidden.empty?

        text = config[:case_sensitive] ? response_text : response_text.downcase

        # Check required keywords
        required_present = required.count do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        # Check forbidden keywords
        forbidden_present = forbidden.count do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        # Calculate score
        total_keywords = required.length + forbidden.length
        required_score = required.empty? ? 0 : (required_present.to_f / required.length) * 100
        forbidden_penalty = forbidden.empty? ? 0 : (forbidden_present.to_f / forbidden.length) * 100

        if required.empty?
          # Only forbidden keywords matter
          (100 - forbidden_penalty).round
        elsif forbidden.empty?
          # Only required keywords matter
          required_score.round
        else
          # Both matter: 70% weight on required, 30% on avoiding forbidden
          ((required_score * 0.7) + ((100 - forbidden_penalty) * 0.3)).round
        end
      end

      def generate_feedback
        required = config[:required_keywords] || []
        forbidden = config[:forbidden_keywords] || []
        text = config[:case_sensitive] ? response_text : response_text.downcase

        missing_required = required.reject do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        found_forbidden = forbidden.select do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        feedback_parts = []

        if missing_required.any?
          feedback_parts << "Missing required keywords: #{missing_required.join(', ')}"
        end

        if found_forbidden.any?
          feedback_parts << "Contains forbidden keywords: #{found_forbidden.join(', ')}"
        end

        if feedback_parts.empty?
          "All keyword requirements met."
        else
          feedback_parts.join(". ")
        end
      end

      def metadata
        super.merge(
          required_keywords: config[:required_keywords],
          forbidden_keywords: config[:forbidden_keywords],
          case_sensitive: config[:case_sensitive]
        )
      end

      # Pass if all required keywords present and no forbidden keywords found
      def passed?
        required = config[:required_keywords] || []
        forbidden = config[:forbidden_keywords] || []
        text = config[:case_sensitive] ? response_text : response_text.downcase

        # Check all required keywords are present
        all_required_present = required.all? do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        # Check no forbidden keywords are present
        no_forbidden_present = forbidden.none? do |keyword|
          search_keyword = config[:case_sensitive] ? keyword : keyword.downcase
          text.include?(search_keyword)
        end

        all_required_present && no_forbidden_present
      end
    end
  end
end
