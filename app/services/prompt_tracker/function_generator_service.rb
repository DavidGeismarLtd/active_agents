# frozen_string_literal: true

require "ruby_llm/schema"

module PromptTracker
  # Service for generating function code from a natural language description.
  # Uses LLM to generate code, parameters, dependencies, and examples.
  #
  # @example Generate a function
  #   result = FunctionGeneratorService.generate(
  #     description: "A function that fetches weather data from an API",
  #     language: "ruby"
  #   )
  #   result[:code]         # => "def execute(city:)\n  # ...\nend"
  #   result[:parameters]   # => { type: "object", properties: {...} }
  #   result[:dependencies] # => ["httparty"]
  #
  class FunctionGeneratorService
    def self.generate(description:, language: "ruby")
      new(description: description, language: language).generate
    end

    def initialize(description:, language:)
      @description = description
      @language = language
    end

    def generate
      schema = build_generation_schema
      prompt = build_generation_prompt
      response = LlmClientService.call_with_schema(
        provider: provider,
        model: model,
        prompt: prompt,
        schema: schema,
        temperature: temperature
      )

      parse_response(response)
    end

    private

    attr_reader :description, :language

    def provider
      PromptTracker.configuration.default_provider_for(:function_generator) || :openai
    end

    def model
      PromptTracker.configuration.default_model_for(:function_generator) || "gpt-4o"
    end

    def temperature
      PromptTracker.configuration.default_temperature_for(:function_generator) || 0.7
    end

    def build_generation_prompt
      <<~PROMPT
        You are an expert software engineer. Generate a complete function based on this description:

        Description: #{description}
        Language: #{language}

        CRITICAL REQUIREMENTS:
        1. Write a TOP-LEVEL `execute` method (NOT a class method, NOT inside a class)
        2. The execute method MUST accept keyword arguments
        3. The execute method MUST return a hash/object with the result
        4. DO NOT wrap the code in a class or module
        5. Include error handling where appropriate
        6. Add helpful comments explaining the logic
        7. Use modern #{language} best practices

        Code Format Examples:

        ✅ CORRECT (Ruby):
        ```ruby
        require 'httparty'

        # Fetches stock price from API
        def execute(symbol:)
          response = HTTParty.get("https://api.example.com/stock/\#{symbol}")
          { success: true, price: response['price'] }
        rescue => e
          { success: false, error: e.message }
        end
        ```

        ❌ WRONG (Don't do this):
        ```ruby
        class StockFetcher  # ❌ NO CLASSES!
          def execute(symbol:)
            # ...
          end
        end
        ```

        Additional guidelines:
        - For Ruby: Use keyword arguments, return hashes with symbol keys
        - For Python: Use type hints, return dictionaries
        - For Node.js: Use async/await if needed, return objects

        Generate:
        1. Function code with the TOP-LEVEL execute method (no classes!)
        2. JSON Schema for the parameters (what arguments the function accepts) - return as JSON string
        3. List of dependencies/packages needed - return as JSON array string (e.g., ["httparty", "json"])
        4. Example input that demonstrates usage - return as JSON object string
        5. Example output showing what the function returns - return as JSON object string
        6. A clear name for the function (snake_case)
        7. A brief description of what it does
        8. A category (e.g., api, data_processing, utility)
      PROMPT
    end

    def build_generation_schema
      Class.new(RubyLLM::Schema) do
        string :name, description: "Function name in snake_case"
        string :description, description: "Brief description of what the function does"
        string :code, description: "Complete function code with execute method"
        string :parameters, description: "JSON Schema defining the function parameters (as JSON string)"
        string :dependencies, description: "List of packages/gems needed (as JSON array string)"
        string :example_input, description: "Example input arguments (as JSON string)"
        string :example_output, description: "Example output result (as JSON string)"
        string :category, description: "Function category (e.g., api, data_processing, utility)"
      end
    end

    def parse_response(response)
      # Response from LlmClientService.call_with_schema returns JSON string in :text
      content = JSON.parse(response[:text])

      {
        name: content["name"],
        description: content["description"],
        code: content["code"],
        parameters: parse_json_field(content["parameters"]),
        dependencies: parse_json_field(content["dependencies"]) || [],
        example_input: parse_json_field(content["example_input"]),
        example_output: parse_json_field(content["example_output"]),
        category: content["category"] || "utility",
        language: language
      }
    end

    def parse_json_field(value)
      return nil if value.nil?
      return value if value.is_a?(Hash) || value.is_a?(Array)

      JSON.parse(value)
    rescue JSON::ParserError
      value
    end
  end
end
