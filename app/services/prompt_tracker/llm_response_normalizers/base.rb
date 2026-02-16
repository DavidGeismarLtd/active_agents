# frozen_string_literal: true

module PromptTracker
  module LlmResponseNormalizers
    # Base class for LLM response normalizers.
    #
    # Each normalizer is responsible for transforming a raw API response
    # into a NormalizedLlmResponse object. This keeps extraction logic
    # in testable, single-responsibility classes.
    #
    # @example
    #   LlmResponseNormalizers::Openai::Responses.normalize(raw_response)
    #   # => NormalizedLlmResponse instance
    #
    class Base
      # Class method to normalize a raw response
      #
      # @param raw_response [Object] the raw API response
      # @return [NormalizedResponse] the normalized response
      def self.normalize(raw_response)
        new(raw_response).normalize
      end

      def initialize(raw_response)
        @raw_response = raw_response
      end

      # Normalize the raw response to a NormalizedResponse
      #
      # @return [NormalizedResponse] the normalized response
      def normalize
        raise NotImplementedError, "Subclasses must implement #normalize"
      end

      private

      attr_reader :raw_response

      # Parse JSON arguments (common utility used by all normalizers)
      #
      # @param args [String, Hash, nil] raw arguments
      # @return [Hash] parsed arguments
      def parse_json_arguments(args)
        return {} if args.nil?
        return args if args.is_a?(Hash)

        JSON.parse(args)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
