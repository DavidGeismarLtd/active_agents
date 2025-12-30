# frozen_string_literal: true

require "json"

module PromptTracker
  module Evaluators
    # Evaluates response based on format requirements.
    #
    # Checks if the response matches expected formats like JSON, markdown, etc.
    #
    # @example Validate JSON format
    #   evaluator = FormatEvaluator.new(response_text, {
    #     format: :json,
    #     required_keys: ["name", "email"]
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Validate markdown format
    #   evaluator = FormatEvaluator.new(response_text, {
    #     format: :markdown,
    #     require_headers: true
    #   })
    #
    class FormatEvaluator < BasePromptVersionEvaluator
      # Supported formats
      FORMATS = %i[json markdown plain_text].freeze

      # Default configuration
      DEFAULT_CONFIG = {
        format: :plain_text,     # Expected format
        required_keys: [],       # For JSON: required top-level keys (deprecated, use schema)
        require_headers: false,  # For markdown: require headers
        max_parse_errors: 0,     # Maximum allowed parse errors
        schema: nil,             # For JSON: schema validation (required_keys, optional_keys, types, nested_structure)
        strict: false            # Strict mode: no extra keys allowed in JSON
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          format: { type: :symbol },
          required_keys: { type: :array },
          require_headers: { type: :boolean },
          max_parse_errors: { type: :integer },
          schema: { type: :json },
          strict: { type: :boolean }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Format Validator",
          description: "Validates response format (JSON, Markdown, etc.)",
          icon: "file-code",
          default_config: DEFAULT_CONFIG
        }
      end

      def initialize(response_text, config = {})
        super(response_text, DEFAULT_CONFIG.merge(config))
        validate_config!
      end

      def evaluate_score
        case config[:format]
        when :json
          evaluate_json_format
        when :markdown
          evaluate_markdown_format
        when :plain_text
          evaluate_plain_text_format
        else
          50 # Unknown format
        end
      end

      def generate_feedback
        case config[:format]
        when :json
          json_feedback
        when :markdown
          markdown_feedback
        when :plain_text
          plain_text_feedback
        else
          "Unknown format: #{config[:format]}"
        end
      end

      def metadata
        super.merge(
          format: config[:format],
          format_valid: format_valid?
        )
      end

      private

      def validate_config!
        unless FORMATS.include?(config[:format])
          raise ArgumentError, "Invalid format: #{config[:format]}. Must be one of: #{FORMATS.join(', ')}"
        end
      end

      def format_valid?
        case config[:format]
        when :json
          json_valid?
        when :markdown
          markdown_valid?
        when :plain_text
          true # Plain text is always valid
        else
          false
        end
      end

      # JSON format evaluation
      def evaluate_json_format
        return 0 unless json_valid?

        parsed = parse_json

        # If schema is provided, use schema validation
        if config[:schema].present?
          return evaluate_json_schema(parsed, config[:schema])
        end

        # Legacy: use required_keys if no schema
        return 100 if config[:required_keys].empty?

        # Check required keys
        missing_keys = config[:required_keys] - parsed.keys
        present_keys = config[:required_keys].length - missing_keys.length

        ((present_keys.to_f / config[:required_keys].length) * 100).round
      end

      def json_valid?
        parse_json
        true
      rescue JSON::ParserError
        false
      end

      def parse_json
        JSON.parse(response_text)
      end

      def json_feedback
        return "Invalid JSON format" unless json_valid?

        parsed = parse_json

        # If schema is provided, use schema feedback
        if config[:schema].present?
          return generate_schema_feedback(parsed, config[:schema])
        end

        # Legacy: use required_keys feedback
        if config[:required_keys].empty?
          "Valid JSON format"
        else
          missing = config[:required_keys] - parsed.keys

          if missing.empty?
            "Valid JSON with all required keys"
          else
            "Valid JSON but missing keys: #{missing.join(', ')}"
          end
        end
      end

      # Validates JSON against a schema
      # Schema format:
      # {
      #   "required_keys": ["key1", "key2"],
      #   "optional_keys": ["key3"],
      #   "types": { "key1": "string", "key2": "integer" },
      #   "nested_structure": { "key1": { "required_keys": [...] } }
      # }
      def evaluate_json_schema(data, schema)
        errors = []
        score = 100

        # Check required keys
        if schema["required_keys"].present?
          missing_keys = schema["required_keys"] - data.keys.map(&:to_s)
          if missing_keys.any?
            errors << "Missing required keys: #{missing_keys.join(', ')}"
            score -= (missing_keys.length.to_f / schema["required_keys"].length * 50).round
          end
        end

        # Check for extra keys in strict mode
        if config[:strict] && (schema["required_keys"].present? || schema["optional_keys"].present?)
          allowed_keys = (schema["required_keys"] || []) + (schema["optional_keys"] || [])
          extra_keys = data.keys.map(&:to_s) - allowed_keys
          if extra_keys.any?
            errors << "Extra keys not allowed in strict mode: #{extra_keys.join(', ')}"
            score -= 20
          end
        end

        # Check types
        if schema["types"].present?
          schema["types"].each do |key, expected_type|
            next unless data.key?(key) || data.key?(key.to_sym)

            value = data[key] || data[key.to_sym]
            unless value_matches_type?(value, expected_type)
              errors << "Key '#{key}' has wrong type (expected #{expected_type}, got #{value.class.name.downcase})"
              score -= 10
            end
          end
        end

        # Check nested structures
        if schema["nested_structure"].present?
          schema["nested_structure"].each do |key, nested_schema|
            next unless data.key?(key) || data.key?(key.to_sym)

            nested_data = data[key] || data[key.to_sym]
            if nested_data.is_a?(Hash)
              nested_score = evaluate_json_schema(nested_data, nested_schema)
              score = [ score, nested_score ].min
            else
              errors << "Key '#{key}' should be an object for nested validation"
              score -= 15
            end
          end
        end

        [ score, 0 ].max
      end

      # Checks if a value matches the expected type
      def value_matches_type?(value, expected_type)
        case expected_type.to_s.downcase
        when "string"
          value.is_a?(String)
        when "integer", "int"
          value.is_a?(Integer)
        when "float", "number"
          value.is_a?(Float) || value.is_a?(Integer)
        when "boolean", "bool"
          value.is_a?(TrueClass) || value.is_a?(FalseClass)
        when "array"
          value.is_a?(Array)
        when "object", "hash"
          value.is_a?(Hash)
        when "null", "nil"
          value.nil?
        else
          true # Unknown type, don't validate
        end
      end

      # Generates feedback for schema validation
      def generate_schema_feedback(data, schema)
        errors = []

        # Check required keys
        if schema["required_keys"].present?
          missing_keys = schema["required_keys"] - data.keys.map(&:to_s)
          errors << "Missing required keys: #{missing_keys.join(', ')}" if missing_keys.any?
        end

        # Check for extra keys in strict mode
        if config[:strict] && (schema["required_keys"].present? || schema["optional_keys"].present?)
          allowed_keys = (schema["required_keys"] || []) + (schema["optional_keys"] || [])
          extra_keys = data.keys.map(&:to_s) - allowed_keys
          errors << "Extra keys: #{extra_keys.join(', ')}" if extra_keys.any?
        end

        # Check types
        if schema["types"].present?
          schema["types"].each do |key, expected_type|
            next unless data.key?(key) || data.key?(key.to_sym)

            value = data[key] || data[key.to_sym]
            unless value_matches_type?(value, expected_type)
              errors << "'#{key}' has wrong type (expected #{expected_type})"
            end
          end
        end

        if errors.empty?
          "Valid JSON matching schema"
        else
          "Schema validation errors: #{errors.join('; ')}"
        end
      end

      # Markdown format evaluation
      def evaluate_markdown_format
        score = 100

        if config[:require_headers] && !has_markdown_headers?
          score -= 50
        end

        score
      end

      def markdown_valid?
        # Basic markdown validation: check for common markdown patterns
        response_text.match?(/[#*_\[\]`]/) || response_text.length > 0
      end

      def has_markdown_headers?
        response_text.match?(/^[#]{1,6}\s+.+/)
      end

      def markdown_feedback
        parts = []

        if config[:require_headers] && !has_markdown_headers?
          parts << "Missing markdown headers"
        end

        parts.empty? ? "Valid markdown format" : parts.join(". ")
      end

      # Plain text format evaluation
      def evaluate_plain_text_format
        response_text.length > 0 ? 100 : 0
      end

      def plain_text_feedback
        response_text.length > 0 ? "Valid plain text" : "Empty response"
      end

      public

      # Pass if format is valid
      def passed?
        format_valid?
      end
    end
  end
end
