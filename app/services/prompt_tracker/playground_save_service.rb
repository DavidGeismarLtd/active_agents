# frozen_string_literal: true

module PromptTracker
  # Service for saving prompts from the playground.
  #
  # Handles four scenarios based on version state:
  # 1. Create new prompt with initial version (standalone mode)
  # 2. Update existing version (development state - no tests/datasets/responses)
  # 3. Create new version (production state - has responses)
  # 4. Create new version (testing state + structural changes)
  #
  # Version States:
  # - Development: No tests, datasets, or llm_responses → free editing
  # - Testing: Has tests OR datasets → structural changes force new version
  # - Production: Has llm_responses → all changes force new version
  #
  # Structural fields that force new version in testing state:
  # - model_config.provider, model_config.api, model_config.model, model_config.tool_config
  # - variables_schema, response_schema
  #
  # @example Updating an existing version (development state)
  #   result = PlaygroundSaveService.call(
  #     params: { user_prompt: "Hello {{name}}", save_action: "update" },
  #     prompt: existing_prompt,
  #     prompt_version: existing_version
  #   )
  #   result.success? # => true
  #   result.version  # => updated version
  #   result.version_created_reason # => nil
  #
  # @example Creating new version due to production state
  #   result = PlaygroundSaveService.call(...)
  #   result.version_created_reason # => :production_immutable
  #
  # @example Creating new version due to structural change
  #   result = PlaygroundSaveService.call(...)
  #   result.version_created_reason # => :structural_change_with_tests
  class PlaygroundSaveService
    Result = Data.define(:success?, :action, :prompt, :version, :errors, :version_created_reason)

    def self.call(params:, prompt: nil, prompt_version: nil)
      new(params: params, prompt: prompt, prompt_version: prompt_version).call
    end

    def initialize(params:, prompt: nil, prompt_version: nil)
      @params = params
      @prompt = prompt
      @prompt_version = prompt_version
    end

    def call
      if prompt
        determine_save_action
      else
        create_new_prompt
      end
    end

    private

    attr_reader :params, :prompt, :prompt_version

    # Determines the appropriate save action based on version state
    def determine_save_action
      if prompt_version.nil?
        create_new_version(reason: nil)
      elsif must_create_new_version?
        create_new_version(reason: version_creation_reason)
      else
        update_existing_version
      end
    end

    # Checks if a new version must be created instead of updating
    #
    # @return [Boolean] true if new version required
    def must_create_new_version?
      return true if params[:save_action] == "new_version"
      return true if prompt_version.production_state?
      return true if prompt_version.testing_state? && structural_fields_changing?

      false
    end

    # Checks if structural fields are being changed
    #
    # @return [Boolean] true if any structural field is different
    def structural_fields_changing?
      old_config = prompt_version.model_config || {}
      new_config = params[:model_config] || {}

      # Check structural model_config keys
      structural_keys_changed = PromptVersion::STRUCTURAL_MODEL_CONFIG_KEYS.any? do |key|
        old_config[key] != new_config[key]
      end

      structural_keys_changed ||
        prompt_version.variables_schema != params[:variables_schema] ||
        prompt_version.response_schema != params[:response_schema]
    end

    # Returns the reason for creating a new version
    #
    # @return [Symbol, nil] :production_immutable, :structural_change_with_tests, :user_requested
    def version_creation_reason
      if params[:save_action] == "new_version"
        :user_requested
      elsif prompt_version.production_state?
        :production_immutable
      elsif prompt_version.testing_state?
        :structural_change_with_tests
      end
    end

    def update_existing_version
      if prompt_version.update(version_attributes)
        success_result(:updated, prompt, prompt_version, version_created_reason: nil)
      else
        failure_result(prompt_version.errors.full_messages)
      end
    end

    def create_new_version(reason:)
      version = prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

      if version.save
        success_result(:created, prompt, version, version_created_reason: reason)
      else
        failure_result(version.errors.full_messages)
      end
    end

    def create_new_prompt
      return failure_result([ "Prompt name is required" ]) if params[:prompt_name].blank?

      new_prompt = Prompt.new(
        name: params[:prompt_name],
        slug: params[:prompt_slug].presence,
        description: params[:notes]
      )
      version = new_prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

      if new_prompt.save
        success_result(:created, new_prompt, version, version_created_reason: nil)
      else
        failure_result(new_prompt.errors.full_messages + version.errors.full_messages)
      end
    end

    def version_attributes
      attrs = {
        user_prompt: params[:user_prompt],
        system_prompt: params[:system_prompt],
        notes: params[:notes],
        model_config: params[:model_config] || {},
        response_schema: params[:response_schema]
      }
      # Only include variables_schema if explicitly provided
      attrs[:variables_schema] = params[:variables_schema] if params.key?(:variables_schema)
      attrs
    end

    def success_result(action, prompt, version, version_created_reason:)
      Result.new(
        success?: true,
        action: action,
        prompt: prompt,
        version: version,
        errors: [],
        version_created_reason: version_created_reason
      )
    end

    def failure_result(errors)
      Result.new(
        success?: false,
        action: nil,
        prompt: nil,
        version: nil,
        errors: errors,
        version_created_reason: nil
      )
    end
  end
end
