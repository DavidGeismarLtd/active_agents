# frozen_string_literal: true

require "ruby_llm/schema"

module PromptTracker
  # Service for generating dataset rows using an LLM.
  #
  # This service uses an LLM with structured outputs to generate realistic,
  # diverse test data rows based on a dataset's variables_schema.
  #
  # @example Generate 10 rows for a dataset
  #   rows = DatasetRowGeneratorService.generate(
  #     dataset: dataset,
  #     count: 10,
  #     instructions: "Focus on edge cases",
  #     model: "gpt-4o"
  #   )
  #
  # @example Generate rows with custom instructions
  #   rows = DatasetRowGeneratorService.generate(
  #     dataset: dataset,
  #     count: 20,
  #     instructions: "Include international names and special characters"
  #   )
  #
  class DatasetRowGeneratorService
    # Maximum number of rows that can be generated in one request
    MAX_ROWS = 100

    # Generate dataset rows using an LLM
    #
    # @param dataset [Dataset] the dataset to generate rows for
    # @param count [Integer] number of rows to generate (1-100)
    # @param instructions [String, nil] custom instructions for generation
    # @param model [String, nil] LLM model to use (defaults to configured dataset_generator_model)
    # @return [Array<DatasetRow>] created dataset rows
    # @raise [ArgumentError] if count is invalid or dataset has no schema
    def self.generate(dataset:, count:, instructions: nil, model: nil)
      new(dataset, count, instructions, model).generate
    end

    attr_reader :dataset, :count, :instructions, :model, :provider, :api

    def initialize(dataset, count, instructions, model)
      @dataset = dataset
      @count = count
      @instructions = instructions
      @model = model || PromptTracker.configuration.dataset_generator_model
      @provider = PromptTracker.configuration.dataset_generator_provider
      @api = PromptTracker.configuration.dataset_generator_api

      validate_params!
    end

    # Generate the rows
    #
    # @return [Array<DatasetRow>] created dataset rows
    def generate
      # Build the generation prompt
      prompt = build_generation_prompt

      # Call LLM with structured output
      generated_data = call_llm(prompt)

      # Create DatasetRow records
      create_rows(generated_data)
    end

    private

    # Validate input parameters
    #
    # @raise [ArgumentError] if parameters are invalid
    def validate_params!
      raise ArgumentError, "Dataset is required" if dataset.nil?
      raise ArgumentError, "Dataset must have a valid schema" if dataset.schema.blank?
      raise ArgumentError, "Count must be between 1 and #{MAX_ROWS}" unless count.between?(1, MAX_ROWS)
    end

    # Build the generation prompt for the LLM
    #
    # @return [String] the prompt text
    def build_generation_prompt
      schema_description = format_schema_for_prompt
      prompt_context = build_prompt_context
      function_context = build_function_context

      prompt = <<~PROMPT
        You are a test data generator for an LLM prompt testing system.

        Generate #{count} diverse, realistic test data rows for testing an LLM prompt.

        #{prompt_context}

        VARIABLES SCHEMA:
        #{schema_description}

        #{function_context}

        REQUIREMENTS:
        1. Generate exactly #{count} rows
        2. Each row must include ALL required variables
        3. Make the data diverse and realistic
        4. Include edge cases (empty strings, special characters, long text, numbers, etc.)
        5. Vary the data appropriately based on variable types
        6. Consider real-world scenarios that would be useful for testing the prompt above
        7. Generate data that will help test different aspects of the prompt's behavior
        #{has_functions? ? "8. IMPORTANT: Each row MUST include a 'mock_function_outputs' field with realistic mock responses for ALL functions defined above" : ""}

        #{instructions.present? ? "CUSTOM INSTRUCTIONS:\n#{instructions}\n" : ""}
        #{build_output_format_example}
      PROMPT

      prompt.strip
    end

    # Build output format example
    #
    # @return [String] example of expected output format
    def build_output_format_example
      if has_functions?
        functions = get_functions
        function_names = functions.first(2).map { |f| f["name"] || f[:name] }

        example = {
          "rows" => [
            dataset.schema.each_with_object({}) do |var_schema, hash|
              hash[var_schema["name"]] = "<value for #{var_schema['name']}>"
            end.merge({
              "mock_function_outputs" => function_names.each_with_object({}) do |func_name, hash|
                hash[func_name] = "<realistic mock response for #{func_name}>"
              end
            })
          ]
        }

        <<~EXAMPLE
          OUTPUT FORMAT:
          Return a JSON object with this structure:
          #{JSON.pretty_generate(example)}

          Note: The mock_function_outputs field is REQUIRED for each row and must include mock responses for all functions.
        EXAMPLE
      else
        <<~EXAMPLE
          OUTPUT FORMAT:
          Return a JSON object with a "rows" array where each row contains the variable values.
        EXAMPLE
      end
    end

    # Build context about the prompt being tested
    #
    # @return [String] formatted prompt context
    def build_prompt_context
      testable = dataset.testable
      context_parts = []

      context_parts << "PROMPT CONTEXT:"

      # Handle PromptVersion testables
      if testable.is_a?(PromptVersion)
        context_parts << "You are generating test data for the following LLM prompt:\n"

        if testable.system_prompt.present?
          context_parts << "System Prompt:"
          context_parts << testable.system_prompt
          context_parts << ""
        end

        context_parts << "User Prompt Template:"
        context_parts << testable.user_prompt
        context_parts << ""
      end

      context_parts.join("\n")
    end

    # Build context about function calling if enabled
    #
    # @return [String] formatted function context
    def build_function_context
      return "" unless has_functions?

      functions = get_functions
      context_parts = []

      context_parts << "FUNCTION CALLING ENABLED:"
      context_parts << "The prompt being tested has function calling enabled with the following functions:\n"

      functions.each do |func|
        context_parts << "Function: #{func['name']}"
        context_parts << "Description: #{func['description']}" if func["description"].present?
        context_parts << "Output Format: #{func['output_description']}" if func["output_description"].present?
        if func["parameters"].present?
          context_parts << "Parameters: #{JSON.pretty_generate(func['parameters'])}"
        end
        context_parts << ""
      end

      context_parts << "For each test row, you MUST generate realistic mock_function_outputs."
      context_parts << "The mock_function_outputs should be an object where keys are function names"
      context_parts << "and values are realistic mock responses that those functions would return."
      context_parts << "Use the 'Output Format' description above to guide what each function should return."
      context_parts << "Make the mock responses relevant to the test row's data and realistic for the function's purpose."
      context_parts << ""

      context_parts.join("\n")
    end

    # Check if the testable has function calling enabled
    #
    # @return [Boolean]
    def has_functions?
      get_functions.present?
    end

    # Get functions from testable's model_config
    #
    # @return [Array<Hash>, nil]
    def get_functions
      testable = dataset.testable
      return nil unless testable.respond_to?(:model_config)

      model_config = testable.model_config&.with_indifferent_access
      return nil unless model_config

      model_config.dig(:tool_config, :functions) || model_config.dig("tool_config", "functions")
    end

    # Format the schema for the prompt
    #
    # @return [String] formatted schema description
    def format_schema_for_prompt
      dataset.schema.map do |var|
        name = var["name"]
        type = var["type"] || "string"
        required = var["required"] ? "REQUIRED" : "optional"
        description = var["description"]

        parts = [ "- #{name} (#{type}, #{required})" ]
        parts << "  Description: #{description}" if description.present?
        parts.join("\n")
      end.join("\n")
    end

    # Build RubyLLM schema for structured output
    #
    # @return [Class] RubyLLM::Schema subclass
    def build_schema
      # Capture dataset schema and functions in local variables for the block
      schema_vars = dataset.schema
      include_functions = has_functions?
      functions = include_functions ? get_functions : []

      # Create dynamic schema class
      Class.new(RubyLLM::Schema) do
        # Define an array of row objects
        array :rows do
          object do
            # Dynamically add fields based on dataset schema
            schema_vars.each do |var|
              var_name = var["name"].to_sym
              var_type = var["type"] || "string"
              var_description = var["description"]

              # Map schema types to RubyLLM field methods
              case var_type
              when "text", "string"
                string var_name, description: var_description
              when "number", "integer"
                number var_name, description: var_description
              when "boolean"
                boolean var_name, description: var_description
              else
                string var_name, description: var_description
              end
            end
            # Add mock_function_outputs field if functions are configured
            # Define explicit properties for each function to guide the LLM
            if include_functions
              object :mock_function_outputs,
                     description: "REQUIRED: Mock responses for each function. Must include ALL functions." do
                # Dynamically add a string field for each function
                functions.each do |func|
                  function_name = (func["name"] || func[:name]).to_sym
                  function_desc = func["description"] || func[:description]
                  string function_name,
                         description: "Mock response data for #{function_name} function. #{function_desc}"
                end
              end
            end
          end
        end
      end
    end

    # Call LLM with structured output
    #
    # @param prompt [String] the generation prompt
    # @return [Hash] parsed response with :rows key
    def call_llm(prompt)
      schema = build_schema

      # Call LLM with structured output
      # Note: provider and api are passed for consistency but ignored by RubyLLM
      # (RubyLLM auto-detects provider from model name)
      response = LlmClientService.call_with_schema(
        provider: provider,
        api: api,
        model: model,
        prompt: prompt,
        schema: schema,
        temperature: 0.8 # Higher temperature for more diversity
      )

      # Parse the response text (it's JSON)
      parsed = JSON.parse(response[:text])

      # Validate we got rows
      unless parsed["rows"].is_a?(Array)
        raise "LLM response did not include 'rows' array"
      end

      # Log the generated data for debugging
      Rails.logger.info("DatasetRowGeneratorService: Generated #{parsed['rows'].length} rows")
      if has_functions?
        parsed["rows"].each_with_index do |row, idx|
          if row["mock_function_outputs"].present?
            Rails.logger.info("  Row #{idx + 1}: Has mock_function_outputs with keys: #{row['mock_function_outputs'].keys.join(', ')}")
          else
            Rails.logger.warn("  Row #{idx + 1}: Missing mock_function_outputs!")
          end
        end
      end

      parsed
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse LLM response: #{e.message}")
      raise "Failed to parse LLM response as JSON"
    end

    # Create DatasetRow records from generated data
    #
    # @param generated_data [Hash] parsed LLM response with :rows key
    # @return [Array<DatasetRow>] created dataset rows
    def create_rows(generated_data)
      rows_data = generated_data["rows"]

      created_rows = rows_data.map do |row_data|
        dataset.dataset_rows.create!(
          row_data: row_data,
          source: "llm_generated",
          metadata: {
            generation_model: model,
            generation_instructions: instructions,
            generated_at: Time.current.iso8601
          }
        )
      end

      Rails.logger.info(
        "Generated #{created_rows.count} rows for dataset #{dataset.id} using #{model}"
      )

      created_rows
    end
  end
end
