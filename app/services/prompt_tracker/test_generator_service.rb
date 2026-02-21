# frozen_string_literal: true

require "ruby_llm/schema"

module PromptTracker
  # Service for generating tests with AI based on a PromptVersion's configuration.
  #
  # Analyzes the prompt's content, variables, tools, and functions to generate
  # comprehensive test cases with appropriate evaluators.
  #
  # @example Generate tests for a prompt version
  #   result = TestGeneratorService.generate(prompt_version: version)
  #   # => { tests: [<Test>, ...], overall_reasoning: "...", count: 4 }
  #
  # @example Generate tests with custom instructions
  #   result = TestGeneratorService.generate(
  #     prompt_version: version,
  #     instructions: "Focus on edge cases with empty inputs"
  #   )
  #
  class TestGeneratorService
    # Configuration context for test generation
    CONTEXT = :test_generation

    # Fallback defaults if context not configured
    FALLBACK_MODEL = "gpt-4o"
    FALLBACK_TEMPERATURE = 0.7

    # Custom error for malformed LLM responses
    class MalformedResponseError < StandardError; end

    def self.generate(prompt_version:, instructions: nil)
      new(prompt_version: prompt_version, instructions: instructions).generate
    end

    def initialize(prompt_version:, instructions: nil)
      @prompt_version = prompt_version
      @instructions = instructions
    end

    def generate
      Rails.logger.info "[TestGeneratorService] Starting generation for PromptVersion##{prompt_version.id}"
      Rails.logger.info "[TestGeneratorService] Instructions: #{instructions.presence || '(none)'}"

      context = build_context
      Rails.logger.debug "[TestGeneratorService] Context built: #{context.keys.join(', ')}"
      Rails.logger.debug "[TestGeneratorService] System prompt length: #{context[:system_prompt]&.length || 0}"
      Rails.logger.debug "[TestGeneratorService] User prompt length: #{context[:user_prompt]&.length || 0}"
      Rails.logger.debug "[TestGeneratorService] Variables: #{context[:variables]&.map { |v| v['name'] }&.join(', ') || 'none'}"
      Rails.logger.debug "[TestGeneratorService] Tools: #{context[:tools].presence || 'none'}"
      Rails.logger.debug "[TestGeneratorService] Functions: #{context[:functions]&.map { |f| f['name'] }&.join(', ') || 'none'}"

      evaluator_schemas = build_evaluator_schemas
      Rails.logger.info "[TestGeneratorService] Available evaluators: #{evaluator_schemas.map { |e| e[:key] }.join(', ')}"

      prompt = build_generation_prompt(context, evaluator_schemas)
      Rails.logger.debug "[TestGeneratorService] Generation prompt length: #{prompt.length} chars"
      Rails.logger.debug "[TestGeneratorService] Generation prompt:\n#{prompt}"

      Rails.logger.info "[TestGeneratorService] Calling LLM with model: #{configured_model}, temperature: #{configured_temperature}"
      chat = RubyLLM.chat(model: configured_model)
        .with_temperature(configured_temperature)
        .with_schema(build_generation_schema)

      response = chat.ask(prompt)
      Rails.logger.info "[TestGeneratorService] LLM response received"
      Rails.logger.debug "[TestGeneratorService] Response content: #{response.content.inspect}"

      result = parse_and_create_tests(response.content)
      Rails.logger.info "[TestGeneratorService] Created #{result[:count]} tests"

      result
    end

    private

    attr_reader :prompt_version, :instructions

    # Get the configured model for test generation.
    # Falls back to FALLBACK_MODEL if not configured.
    #
    # @return [String] the model ID
    def configured_model
      PromptTracker.configuration.default_model_for(CONTEXT) || FALLBACK_MODEL
    end

    # Get the configured temperature for test generation.
    # Falls back to FALLBACK_TEMPERATURE if not configured.
    #
    # @return [Float] the temperature value
    def configured_temperature
      PromptTracker.configuration.default_temperature_for(CONTEXT) || FALLBACK_TEMPERATURE
    end

    # Build context from the prompt version for the generation prompt
    #
    # @return [Hash] context data
    def build_context
      {
        prompt_name: prompt_version.prompt.name,
        system_prompt: prompt_version.system_prompt,
        user_prompt: prompt_version.user_prompt,
        variables: prompt_version.variables_schema || [],
        model_config: prompt_version.model_config || {},
        tools: extract_tools,
        functions: extract_functions,
        response_schema: prompt_version.response_schema,
        api_type: prompt_version.api_type
      }
    end

    # Extract tools from model_config
    #
    # @return [Array] array of tool names
    def extract_tools
      prompt_version.model_config&.dig("tools") || []
    end

    # Extract functions from model_config
    #
    # @return [Array] array of function definitions
    def extract_functions
      prompt_version.model_config&.dig("tool_config", "functions") || []
    end

    # Build evaluator schemas from the registry for compatible evaluators
    #
    # @return [Array<Hash>] array of evaluator schema definitions
    def build_evaluator_schemas
      EvaluatorRegistry.for_testable(prompt_version).map do |key, meta|
        evaluator_class = meta[:evaluator_class]

        {
          key: key.to_s,
          name: meta[:name],
          description: meta[:description],
          param_schema: evaluator_class.param_schema,
          default_config: meta[:default_config]
        }
      end
    end

    # Build the RubyLLM schema for structured output
    #
    # @return [Class] schema class
    def build_generation_schema
      Class.new(RubyLLM::Schema) do
        array :tests, description: "Array of test cases to create" do
          object do
            string :name, description: "Snake_case test name (e.g., test_greeting_premium_user)"
            string :description, description: "What this test validates"
            string :reasoning, description: "Why this test case is important"

            array :evaluator_configs, description: "Evaluators for this test" do
              object do
                string :evaluator_key, description: "Evaluator type key (e.g., llm_judge, keyword, format)"
                # Config is a JSON string since evaluator configs vary widely
                string :config_json, description: "JSON string of evaluator config (e.g., '{\"keywords\": [\"hello\"]}' or '{\"min_length\": 50}')"
              end
            end
          end
        end

        string :overall_reasoning, description: "Overview of the test strategy"
      end
    end

    # Build the generation prompt with full context
    #
    # @param context [Hash] the prompt version context
    # @param evaluator_schemas [Array<Hash>] available evaluator schemas
    # @return [String] the generation prompt
    def build_generation_prompt(context, evaluator_schemas)
      <<~PROMPT
        You are an expert QA engineer creating test cases for an LLM prompt.

        ## PROMPT TO TEST

        **Name**: #{context[:prompt_name]}

        **System Prompt**:
        #{context[:system_prompt].presence || "(No system prompt)"}

        **User Prompt Template**:
        #{context[:user_prompt]}

        **Variables**:
        #{format_variables(context[:variables])}

        **API Type**: #{context[:api_type] || "Standard chat completion"}

        **Tools Enabled**: #{context[:tools].presence&.join(", ") || "None"}

        **Functions Available**:
        #{format_functions(context[:functions])}

        **Structured Output Schema**: #{context[:response_schema].present? ? "Yes" : "No"}
        #{context[:response_schema].present? ? JSON.pretty_generate(context[:response_schema]) : ""}

        ## AVAILABLE EVALUATORS

        #{format_evaluator_schemas(evaluator_schemas)}

        ## USER INSTRUCTIONS

        #{instructions.presence || "Generate a comprehensive test suite covering happy paths, edge cases, and any tool/function usage validation."}

        ## TASK

        Generate 3-6 test cases that thoroughly validate this prompt. For each test:

        1. **name**: A descriptive snake_case name (e.g., test_greeting_premium_user, test_empty_input_handling)
        2. **description**: Clear explanation of what this test validates
        3. **evaluator_configs**: Array of evaluators to run, each with:
           - **evaluator_key**: One of the available evaluator keys listed above
           - **config_json**: A JSON string of the configuration object matching that evaluator's param_schema (e.g., '{"keywords": ["hello"]}' or '{"min_length": 50}')
        4. **reasoning**: Why this test case is important

        ## GUIDELINES

        - Include at least one test for the "happy path" (normal expected usage)
        - Include edge cases (empty inputs, very long inputs, special characters)
        - If tools are enabled (web_search, code_interpreter, file_search), add tests that verify tool usage
        - If functions are defined, add tests with function_call evaluator
        - If structured output is expected, add format evaluator
        - Always include at least one llm_judge evaluator for quality assessment
        - Use keyword evaluator when specific terms must/must not appear
        - Use length evaluator when response length matters

        Generate the test cases now.
      PROMPT
    end

    # Format variables for display in the prompt
    #
    # @param variables [Array] array of variable definitions
    # @return [String] formatted variables
    def format_variables(variables)
      return "None" if variables.blank?

      variables.map do |v|
        "- #{v['name']} (#{v['type']}, required: #{v['required']})"
      end.join("\n")
    end

    # Format functions for display in the prompt
    #
    # @param functions [Array] array of function definitions
    # @return [String] formatted functions
    def format_functions(functions)
      return "None" if functions.blank?

      functions.map do |f|
        params = f["parameters"]&.dig("properties")&.keys&.join(", ") || "none"
        "- #{f['name']}: #{f['description'] || 'No description'} (params: #{params})"
      end.join("\n")
    end

    # Format evaluator schemas for display in the prompt
    #
    # @param evaluator_schemas [Array<Hash>] array of evaluator schema definitions
    # @return [String] formatted evaluator schemas
    def format_evaluator_schemas(evaluator_schemas)
      evaluator_schemas.map do |es|
        config_fields = es[:param_schema].map do |field, type_info|
          "    - #{field}: #{type_info[:type]}"
        end.join("\n")

        <<~EVALUATOR
          ### #{es[:name]} (key: "#{es[:key]}")
          #{es[:description]}

          **Config fields**:
          #{config_fields}

          **Defaults**: #{es[:default_config].to_json}
        EVALUATOR
      end.join("\n")
    end

    # Parse the LLM response and create Test records
    #
    # @param response_content [Hash] the structured response from the LLM
    # @return [Hash] result with created tests, reasoning, and count
    def parse_and_create_tests(response_content)
      Rails.logger.info "[TestGeneratorService] Parsing response and creating tests"
      Rails.logger.debug "[TestGeneratorService] Response content type: #{response_content.class}"
      Rails.logger.debug "[TestGeneratorService] Response content: #{response_content.inspect}"

      content = response_content.with_indifferent_access

      # Validate response structure
      validate_response_structure!(content)

      # If tests are strings (just names), expand them with a follow-up LLM call
      if content[:tests].first.is_a?(String)
        Rails.logger.info "[TestGeneratorService] Detected string test names, expanding with follow-up call"
        content = expand_string_tests(content)
      end

      Rails.logger.info "[TestGeneratorService] Found #{content[:tests].size} tests in response"
      Rails.logger.debug "[TestGeneratorService] Overall reasoning: #{content[:overall_reasoning]}"

      created_tests = []

      content[:tests].each_with_index do |test_data, index|
        Rails.logger.info "[TestGeneratorService] Creating test #{index + 1}: #{test_data[:name]}"
        Rails.logger.debug "[TestGeneratorService] Test data: #{test_data.inspect}"

        test = prompt_version.tests.create!(
          name: test_data[:name],
          description: test_data[:description],
          enabled: true,
          metadata: {
            ai_generated: true,
            reasoning: test_data[:reasoning],
            generated_at: Time.current.iso8601
          }
        )
        Rails.logger.debug "[TestGeneratorService] Created Test##{test.id}"

        test_data[:evaluator_configs].each_with_index do |ec_data, ec_index|
          evaluator_key = ec_data[:evaluator_key]
          Rails.logger.debug "[TestGeneratorService] Processing evaluator #{ec_index + 1}: #{evaluator_key}"

          registry_entry = EvaluatorRegistry.get(evaluator_key)
          if registry_entry.nil?
            Rails.logger.warn "[TestGeneratorService] Evaluator key '#{evaluator_key}' not found in registry, skipping"
            next
          end

          # Parse config from JSON string if provided
          config_json = ec_data[:config_json]
          Rails.logger.debug "[TestGeneratorService] Config JSON: #{config_json.inspect}"

          config = parse_config(config_json)
          Rails.logger.debug "[TestGeneratorService] Parsed config: #{config.inspect}"

          evaluator_config = test.evaluator_configs.create!(
            evaluator_type: registry_entry[:evaluator_class].name,
            config: config,
            enabled: true
          )
          Rails.logger.debug "[TestGeneratorService] Created EvaluatorConfig##{evaluator_config.id} (#{registry_entry[:evaluator_class].name})"
        end

        created_tests << test
      end

      Rails.logger.info "[TestGeneratorService] Successfully created #{created_tests.size} tests"

      {
        tests: created_tests,
        overall_reasoning: content[:overall_reasoning],
        count: created_tests.size
      }
    end

    # Validate that the LLM response has the expected structure
    #
    # @param content [HashWithIndifferentAccess] the response content
    # @raise [MalformedResponseError] if structure is invalid
    def validate_response_structure!(content)
      unless content[:tests].is_a?(Array)
        raise MalformedResponseError, "LLM response missing 'tests' array (got #{content[:tests].class})"
      end

      if content[:tests].empty?
        raise MalformedResponseError, "LLM response 'tests' array is empty"
      end
    end

    # Parse config JSON string to hash
    #
    # @param config_json [String, nil] JSON string or nil
    # @return [Hash] parsed config or empty hash
    def parse_config(config_json)
      return {} if config_json.blank?

      parsed = JSON.parse(config_json)
      Rails.logger.debug "[TestGeneratorService] Parsed JSON config: #{parsed.inspect}"
      parsed
    end

    # Expand string test names into full test objects with a follow-up LLM call
    #
    # @param content [HashWithIndifferentAccess] the initial response with string test names
    # @return [HashWithIndifferentAccess] expanded response with full test objects
    def expand_string_tests(content)
      test_names = content[:tests]
      overall_reasoning = content[:overall_reasoning]

      prompt = <<~PROMPT
        You previously suggested these test names for an LLM prompt:

        #{test_names.map { |n| "- #{n}" }.join("\n")}

        Overall reasoning: #{overall_reasoning}

        Now, for each test, provide the full details including:
        1. name: The test name (use the names above)
        2. description: What this test validates
        3. reasoning: Why this test case is important
        4. evaluator_configs: Array of evaluators, each with:
           - evaluator_key: One of: #{EvaluatorRegistry.all.keys.join(', ')}
           - config_json: JSON string with the evaluator configuration

        Generate the full test details now.
      PROMPT

      Rails.logger.info "[TestGeneratorService] Making follow-up call to expand test names"

      chat = RubyLLM.chat(model: configured_model)
        .with_temperature(configured_temperature)
        .with_schema(build_generation_schema)

      response = chat.ask(prompt)
      Rails.logger.debug "[TestGeneratorService] Expanded response: #{response.content.inspect}"

      response.content.with_indifferent_access
    end
  end
end
