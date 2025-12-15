# frozen_string_literal: true

require "ruby_llm/schema"

module PromptTracker
  # Service for AI-powered prompt enhancement and generation.
  #
  # This service uses an LLM to either enhance existing prompts or generate
  # new prompts from scratch. It intelligently detects Liquid variables and
  # suggests relevant ones based on context.
  #
  # @example Enhance existing prompts
  #   result = PromptEnhancerService.enhance(
  #     system_prompt: "You are a helpful assistant.",
  #     user_prompt: "Help the user with {{task}}",
  #     context: "customer support"
  #   )
  #   result[:system_prompt]  # => Enhanced system prompt
  #   result[:user_prompt]    # => Enhanced user prompt with variables
  #   result[:suggested_variables] # => ["task", "customer_name", ...]
  #
  # @example Generate from scratch
  #   result = PromptEnhancerService.enhance(
  #     system_prompt: "",
  #     user_prompt: "",
  #     context: "email generator"
  #   )
  #
  class PromptEnhancerService
    # Default model for enhancement (fast and cost-effective)
    DEFAULT_MODEL = ENV.fetch("PROMPT_ENHANCER_MODEL", "gpt-4o-mini")
    DEFAULT_TEMPERATURE = ENV.fetch("PROMPT_ENHANCER_TEMPERATURE", "0.7").to_f

    # Enhance or generate prompts using an LLM
    #
    # @param system_prompt [String] current system prompt (empty for generation)
    # @param user_prompt [String] current user prompt (empty for generation)
    # @param context [String] optional context about the prompt's purpose
    # @return [Hash] enhanced prompts and suggested variables
    def self.enhance(system_prompt: "", user_prompt: "", context: nil)
      new(
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        context: context
      ).enhance
    end

    attr_reader :system_prompt, :user_prompt, :context

    def initialize(system_prompt:, user_prompt:, context: nil)
      @system_prompt = system_prompt.to_s.strip
      @user_prompt = user_prompt.to_s.strip
      @context = context.to_s.strip
    end

    # Perform the enhancement
    #
    # @return [Hash] with :system_prompt, :user_prompt, :suggested_variables, :explanation
    def enhance
      # Build the enhancement prompt
      enhancement_prompt = build_enhancement_prompt

      # Build schema for structured output
      schema = build_schema

      # Call LLM with structured output
      response = LlmClientService.call_with_schema(
        provider: "openai", # Ignored by RubyLLM, auto-detected from model
        model: DEFAULT_MODEL,
        prompt: enhancement_prompt,
        schema: schema,
        temperature: DEFAULT_TEMPERATURE
      )

      # Parse response (it's JSON)
      parsed = JSON.parse(response[:text])

      # Return structured result
      {
        system_prompt: parsed["system_prompt"] || "",
        user_prompt: parsed["user_prompt"] || "",
        suggested_variables: parsed["suggested_variables"] || [],
        explanation: parsed["explanation"] || "Prompt enhanced successfully"
      }
    end

    private

    # Build the enhancement prompt based on mode (enhance vs generate)
    def build_enhancement_prompt
      if generation_mode?
        build_generation_prompt
      else
        build_enhancement_prompt_text
      end
    end

    # Check if we're in generation mode (both prompts empty)
    def generation_mode?
      system_prompt.empty? && user_prompt.empty?
    end

    # Build prompt for enhancing existing content
    def build_enhancement_prompt_text
      <<~PROMPT
        You are an expert prompt engineer. Improve the following prompt template by:

        1. Making it clearer, more specific, and more effective
        2. Adding or improving Liquid template variables using {{ variable_name }} syntax
        3. Following prompt engineering best practices
        4. Maintaining the original intent and purpose
        5. Ensuring the system prompt clearly defines the AI's role and constraints
        6. Ensuring the user prompt is well-structured and actionable

        Current System Prompt:
        #{system_prompt.present? ? system_prompt : "(empty)"}

        Current User Prompt:
        #{user_prompt.present? ? user_prompt : "(empty)"}

        #{context.present? ? "Context/Purpose: #{context}" : ""}

        Provide:
        - An enhanced system_prompt (can be empty if not needed)
        - An enhanced user_prompt with appropriate Liquid variables
        - A list of suggested_variables (variable names without {{ }})
        - A brief explanation of the improvements made

        Use Liquid syntax for variables: {{ variable_name }}
        Suggest meaningful variable names like: customer_name, product_description, issue_type, etc.
      PROMPT
    end

    # Build prompt for generating from scratch
    def build_generation_prompt
      context_text = context.present? ? context : "a general-purpose assistant"

      <<~PROMPT
        You are an expert prompt engineer. Generate a professional prompt template for: #{context_text}

        Create:
        1. A clear system_prompt that defines the AI's role, behavior, and constraints
        2. A well-structured user_prompt with relevant Liquid template variables using {{ variable_name }} syntax
        3. Suggest meaningful variables that would be useful for this type of prompt

        Follow prompt engineering best practices:
        - Be specific and clear
        - Define the AI's role and expertise
        - Include relevant constraints or guidelines
        - Use Liquid variables for dynamic content: {{ variable_name }}

        Provide:
        - A system_prompt that sets up the AI's role
        - A user_prompt with appropriate Liquid variables
        - A list of suggested_variables (variable names without {{ }})
        - A brief explanation of the prompt's design

        Suggest meaningful variable names like: customer_name, product_description, issue_type, etc.
      PROMPT
    end

    # Build RubyLLM schema for structured output
    def build_schema
      Class.new(RubyLLM::Schema) do
        string :system_prompt, description: "The enhanced or generated system prompt"
        string :user_prompt, description: "The enhanced or generated user prompt with Liquid variables"
        array :suggested_variables, description: "List of variable names (without {{ }})" do
          string
        end
        string :explanation, description: "Brief explanation of improvements or design choices"
      end
    end
  end
end
