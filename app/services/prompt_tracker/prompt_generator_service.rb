require "ruby_llm/schema"

module PromptTracker
  # Service for generating prompts from scratch based on a user description.
  # Uses a multi-step approach:
  # 1. Understand and expand the brief description
  # 2. Propose dynamic variables
  # 3. Generate system and user prompts with variables
  class PromptGeneratorService
    DEFAULT_MODEL = ENV.fetch("PROMPT_GENERATOR_MODEL", "gpt-4o-mini")
    DEFAULT_TEMPERATURE = 0.7

    def self.generate(description:)
      new(description: description).generate
    end

    def initialize(description:)
      @description = description
    end

    def generate
      expanded_requirements = understand_and_expand
      variables = propose_variables(expanded_requirements)
      generate_prompts(expanded_requirements, variables)
    end

    private

    attr_reader :description

    def understand_and_expand
      prompt = <<~PROMPT
        You are an expert prompt engineer. A user has provided a brief description of what they want their prompt to do.

        User's description:
        #{description}

        Analyze this description and expand it into detailed requirements. Consider:
        - What is the main purpose and goal?
        - Who is the audience or user?
        - What tone and style would be appropriate?
        - What key capabilities or features are needed?
        - What constraints or guidelines should be followed?

        Provide a comprehensive expansion of the requirements in 2-3 paragraphs.
      PROMPT

      chat = RubyLLM.chat(model: DEFAULT_MODEL).with_temperature(DEFAULT_TEMPERATURE)
      response = chat.ask(prompt)
      response.content
    end

    def propose_variables(requirements)
      prompt = <<~PROMPT
        Based on these prompt requirements, identify dynamic variables that should be included.

        Requirements:
        #{requirements}

        Think about what information would need to change between different uses of this prompt.
        Examples: customer_name, issue_type, product_name, date, context, etc.

        List 3-5 variable names that would make this prompt flexible and reusable.
        Use snake_case for variable names.
        Return ONLY the variable names, one per line, nothing else.
      PROMPT

      chat = RubyLLM.chat(model: DEFAULT_MODEL).with_temperature(DEFAULT_TEMPERATURE)
      response = chat.ask(prompt)

      # Parse variable names from response
      response.content.split("\n").map(&:strip).reject(&:empty?).map { |v| v.gsub(/^-\s*/, "") }
    end

    def generate_prompts(requirements, variables)
      schema = build_generation_schema
      prompt = build_generation_prompt(requirements, variables)

      chat = RubyLLM.chat(model: DEFAULT_MODEL)
        .with_temperature(DEFAULT_TEMPERATURE)
        .with_schema(schema)

      response = chat.ask(prompt)

      # Response.content is a hash with the structured data
      parse_generation_response(response.content, variables)
    end

    def build_generation_prompt(requirements, variables)
      variables_section = if variables.any?
        "Include these Liquid variables in the prompts where appropriate: #{variables.map { |v| "{{ #{v} }}" }.join(', ')}"
      else
        "If helpful, include Liquid variables using {{ variable_name }} syntax."
      end

      <<~PROMPT
        You are an expert prompt engineer following industry best practices. Create effective system and user prompts based on these requirements.

        Requirements:
        #{requirements}

        #{variables_section}

        IMPORTANT - Use structured sections in your prompts:
        Structure your prompts using these sections (use the ones that are relevant):
        - #role - Define the AI persona, expertise, and capabilities
        - #goal - Specify the main objective or task
        - #context - Provide background information
        - #format - Specify output format and structure
        - #example - Show what good output looks like
        - #audience - Describe who will read the output
        - #tone and style - Suggest appropriate tone
        - #what to prioritise - Highlight key aspects to focus on
        - #out of scope - Define limits and boundaries
        - #resources - Mention any resources that could be used

        Guidelines:
        - System prompt: Use sections like #role, #goal, #tone and style to structure the AI's behavior
        - User prompt: Use sections like #context, #format, #example to structure the user's request
        - Include Liquid variables using {{ variable_name }} syntax where dynamic content is needed
        - Make prompts clear, specific, and well-structured
        - Each section should start on a new line with the # prefix
        - Ensure the prompts work well together

        Generate the prompts now with proper section structure.
      PROMPT
    end

    def build_generation_schema
      Class.new(RubyLLM::Schema) do
        string :system_prompt, description: "The system prompt that defines the AI's role and behavior"
        string :user_prompt, description: "The user prompt template with {{ variables }} for dynamic content"
        string :explanation, description: "Brief explanation of the prompt design and how to use it"
      end
    end

    def parse_generation_response(content, variables)
      # Content is a hash with string or symbol keys from RubyLLM
      content = content.with_indifferent_access if content.respond_to?(:with_indifferent_access)

      {
        system_prompt: content[:system_prompt] || content["system_prompt"] || "",
        user_prompt: content[:user_prompt] || content["user_prompt"] || "",
        variables: variables,
        explanation: content[:explanation] || content["explanation"] || "Prompt generated successfully"
      }
    end
  end
end
