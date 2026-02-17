# frozen_string_literal: true

module PromptTracker
  # Parses structured output responses from LLM models.
  #
  # Some LLM providers (particularly Anthropic/Claude) return structured output
  # as a String wrapped in markdown code blocks rather than a parsed Hash.
  #
  # This parser handles:
  # - JSON wrapped in ```json ... ``` markdown code blocks
  # - JSON wrapped in ``` ... ``` code blocks
  # - Raw JSON strings
  # - Already-parsed Hash objects (passthrough)
  #
  # @example Parse a response
  #   response = chat.ask(prompt)  # response.content is a String
  #   parser = StructuredOutputParser.new(response.content)
  #   parsed = parser.parse
  #   # => { "overall_score" => 75, "feedback" => "..." }
  #
  # @example Use class method for convenience
  #   parsed = StructuredOutputParser.parse(response.content)
  #
  class StructuredOutputParser
    # Regex to match JSON in markdown code blocks
    # Handles: ```json\n{...}\n``` or ```\n{...}\n```
    MARKDOWN_JSON_REGEX = /```(?:json)?\s*\n?(.*?)\n?```/m

    attr_reader :content

    # @param content [String, Hash] the response content to parse
    def initialize(content)
      @content = content
    end

    # Class method for convenient one-liner usage
    #
    # @param content [String, Hash] the response content to parse
    # @return [Hash] parsed JSON as a hash with indifferent access
    def self.parse(content)
      new(content).parse
    end

    # Parse the content and return a hash
    #
    # @return [HashWithIndifferentAccess] parsed content
    def parse
      parsed = extract_and_parse_json
      parsed.with_indifferent_access
    end

    private

    # Extract JSON from content and parse it
    #
    # @return [Hash] the parsed JSON
    def extract_and_parse_json
      return content if content.is_a?(Hash)

      json_string = extract_json_string
      JSON.parse(json_string)
    end

    # Extract the JSON string from various formats
    #
    # @return [String] the extracted JSON string
    def extract_json_string
      # Try to extract from markdown code blocks first
      if (match = content.match(MARKDOWN_JSON_REGEX))
        return match[1].strip
      end

      # Otherwise assume it's raw JSON
      content.strip
    end
  end
end
