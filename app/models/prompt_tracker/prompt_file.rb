# frozen_string_literal: true

require "yaml"

module PromptTracker
  # Represents a YAML prompt file on disk.
  #
  # This is NOT an ActiveRecord model - it's a plain Ruby object that
  # represents a .yml file in the prompts directory.
  #
  # @example Loading a prompt file
  #   file = PromptFile.new("app/prompts/support/greeting.yml")
  #   file.valid?  # => true
  #   file.name    # => "support_greeting"
  #   file.user_prompt  # => "Hello {{name}}"
  #
  # @example Expected YAML structure
  #   # app/prompts/support/greeting.yml
  #   name: support_greeting
  #   description: Greeting for customer support
  #   system_prompt: You are a helpful customer support agent.
  #   user_prompt: |
  #     Hello {{customer_name}}!
  #     How can I help you today?
  #   variables:
  #     - name: customer_name
  #       type: string
  #       required: true
  #   model_config:
  #     temperature: 0.7
  #     max_tokens: 150
  #
  class PromptFile
    attr_reader :path, :errors

    # Required fields in YAML file
    REQUIRED_FIELDS = %w[name user_prompt].freeze

    # Optional fields in YAML file
    OPTIONAL_FIELDS = %w[description category tags variables model_config notes system_prompt].freeze

    # All valid fields
    ALL_FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze

    # Initialize a new PromptFile from a file path.
    #
    # @param path [String] absolute or relative path to YAML file
    def initialize(path)
      @path = path
      @errors = []
      @data = nil
      @parsed = false
    end

    # Parse and validate the YAML file.
    #
    # @return [Boolean] true if valid, false otherwise
    def valid?
      parse unless @parsed
      @errors.empty?
    end

    # Get the prompt name from the YAML file.
    #
    # @return [String, nil] the prompt name
    def name
      data["name"]
    end

    # Get the user_prompt from the YAML file.
    #
    # @return [String, nil] the user prompt
    def user_prompt
      data["user_prompt"]
    end

    # Get the system_prompt from the YAML file.
    #
    # @return [String, nil] the system prompt
    def system_prompt
      data["system_prompt"]
    end

    # Get the description from the YAML file.
    #
    # @return [String, nil] the description
    def description
      data["description"]
    end

    # Get the variables schema from the YAML file.
    #
    # @return [Array<Hash>] the variables schema (empty array if not specified)
    def variables
      data["variables"] || []
    end

    # Get the model config from the YAML file.
    #
    # @return [Hash] the model config (empty hash if not specified)
    def model_config
      data["model_config"] || {}
    end

    # Get the notes from the YAML file.
    #
    # @return [String, nil] the notes
    def notes
      data["notes"]
    end

    # Check if the file exists on disk.
    #
    # @return [Boolean] true if file exists
    def exists?
      File.exist?(@path)
    end

    # Get the file's last modified time.
    #
    # @return [Time, nil] last modified time or nil if file doesn't exist
    def last_modified
      File.mtime(@path) if exists?
    end

    # Get the relative path from the prompts directory.
    #
    # @return [String] relative path
    def relative_path
      @path.sub(PromptTracker.configuration.prompts_path + "/", "")
    end

    # Convert to hash suitable for creating/updating a Prompt and PromptVersion.
    #
    # @return [Hash] hash with :prompt and :version keys
    def to_h
      {
        prompt: {
          name: name,
          description: description
        },
        version: {
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          variables_schema: variables,
          model_config: model_config,
          notes: notes,
          source: "file"
        }
      }
    end

    # Get a human-readable summary of this file.
    #
    # @return [String] summary
    def summary
      "#{name} (#{relative_path})"
    end

    private

    # Get the parsed data hash.
    #
    # @return [Hash] the parsed YAML data
    def data
      parse unless @parsed
      @data || {}
    end

    # Parse the YAML file and validate it.
    def parse
      @parsed = true
      @errors = []

      # Check file exists
      unless exists?
        @errors << "File does not exist: #{@path}"
        return
      end

      # Parse YAML
      begin
        @data = YAML.load_file(@path)
      rescue Psych::SyntaxError => e
        @errors << "Invalid YAML syntax: #{e.message}"
        return
      end

      # Validate data is a hash
      unless @data.is_a?(Hash)
        @errors << "YAML file must contain a hash/object at the root level"
        return
      end

      # Validate required fields
      validate_required_fields
      validate_field_types
      validate_name_format
      validate_template_variables
    end

    # Validate that all required fields are present.
    def validate_required_fields
      REQUIRED_FIELDS.each do |field|
        if @data[field].nil? || @data[field].to_s.strip.empty?
          @errors << "Missing required field: #{field}"
        end
      end
    end

    # Validate field types.
    def validate_field_types
      # name must be a string
      if @data["name"] && !@data["name"].is_a?(String)
        @errors << "Field 'name' must be a string"
      end

      # user_prompt must be a string
      if @data["user_prompt"] && !@data["user_prompt"].is_a?(String)
        @errors << "Field 'user_prompt' must be a string"
      end

      # system_prompt must be a string if present
      if @data["system_prompt"] && !@data["system_prompt"].is_a?(String)
        @errors << "Field 'system_prompt' must be a string"
      end

      # variables must be an array
      if @data["variables"] && !@data["variables"].is_a?(Array)
        @errors << "Field 'variables' must be an array"
      end

      # model_config must be a hash
      if @data["model_config"] && !@data["model_config"].is_a?(Hash)
        @errors << "Field 'model_config' must be a hash"
      end
    end

    # Validate name format (must be lowercase with underscores).
    def validate_name_format
      return unless @data["name"].is_a?(String)

      unless @data["name"].match?(/\A[a-z0-9_]+\z/)
        @errors << "Field 'name' must contain only lowercase letters, numbers, and underscores"
      end
    end

    # Validate that variables in user_prompt match variables schema.
    def validate_template_variables
      return unless @data["user_prompt"].is_a?(String)
      return unless @data["variables"].is_a?(Array)

      # Extract variables from user_prompt ({{variable_name}})
      template_vars = @data["user_prompt"].scan(/\{\{(\w+)\}\}/).flatten.uniq

      # Extract variable names from schema
      schema_vars = @data["variables"].map { |v| v["name"] }.compact

      # Check for variables in user_prompt that aren't in schema
      missing_in_schema = template_vars - schema_vars
      if missing_in_schema.any?
        @errors << "User prompt uses variables not defined in schema: #{missing_in_schema.join(', ')}"
      end

      # Warn about variables in schema that aren't used in user_prompt
      # (This is just a warning, not an error)
      unused_vars = schema_vars - template_vars
      if unused_vars.any?
        # We could add warnings here, but for now we'll just allow it
        # @warnings << "Variables defined but not used in user_prompt: #{unused_vars.join(', ')}"
      end
    end
  end
end
