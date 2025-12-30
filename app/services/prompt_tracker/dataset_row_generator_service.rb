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

    # Default LLM model for generation (must support structured outputs)
    DEFAULT_MODEL = "gpt-4o"

    # Generate dataset rows using an LLM
    #
    # @param dataset [Dataset] the dataset to generate rows for
    # @param count [Integer] number of rows to generate (1-100)
    # @param instructions [String, nil] custom instructions for generation
    # @param model [String] LLM model to use
    # @return [Array<DatasetRow>] created dataset rows
    # @raise [ArgumentError] if count is invalid or dataset has no schema
    def self.generate(dataset:, count:, instructions: nil, model: DEFAULT_MODEL)
      new(dataset, count, instructions, model).generate
    end

    attr_reader :dataset, :count, :instructions, :model

    def initialize(dataset, count, instructions, model)
      @dataset = dataset
      @count = count
      @instructions = instructions
      @model = model

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

      prompt = <<~PROMPT
        You are a test data generator for an LLM prompt testing system.

        Generate #{count} diverse, realistic test data rows for testing an LLM prompt.

        #{prompt_context}

        VARIABLES SCHEMA:
        #{schema_description}

        REQUIREMENTS:
        1. Generate exactly #{count} rows
        2. Each row must include ALL required variables
        3. Make the data diverse and realistic
        4. Include edge cases (empty strings, special characters, long text, numbers, etc.)
        5. Vary the data appropriately based on variable types
        6. Consider real-world scenarios that would be useful for testing the prompt above
        7. Generate data that will help test different aspects of the prompt's behavior

        #{instructions.present? ? "CUSTOM INSTRUCTIONS:\n#{instructions}\n" : ""}
        Return the data as a structured JSON response with a "rows" array.
        Each row should be an object with keys matching the variable names.
      PROMPT

      prompt.strip
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
      elsif testable.is_a?(Openai::Assistant)
        # Handle Assistant testables
        context_parts << "You are generating test data for the following OpenAI Assistant:\n"
        context_parts << "Assistant Name: #{testable.name}"
        context_parts << "Description: #{testable.description}" if testable.description.present?
        context_parts << ""
      end

      context_parts.join("\n")
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
      # Capture dataset schema in a local variable for the block
      schema_vars = dataset.schema

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
      response = LlmClientService.call_with_schema(
        provider: "openai", # Ignored by RubyLLM, auto-detected from model
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
