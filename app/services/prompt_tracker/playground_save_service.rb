# frozen_string_literal: true

module PromptTracker
  # Service for saving prompts from the playground.
  # Handles three scenarios:
  # 1. Update existing version (if no responses exist)
  # 2. Create new version for existing prompt
  # 3. Create new prompt with initial version (standalone mode)
  #
  # @example Updating an existing version
  #   result = PlaygroundSaveService.call(
  #     params: { user_prompt: "Hello {{name}}", save_action: "update" },
  #     prompt: existing_prompt,
  #     prompt_version: existing_version
  #   )
  #   result.success? # => true
  #   result.version  # => updated version
  #
  # @example Creating a new prompt
  #   result = PlaygroundSaveService.call(
  #     params: { user_prompt: "Hello", prompt_name: "Greeting" }
  #   )
  #   result.prompt   # => new prompt
  #   result.version  # => new version
  class PlaygroundSaveService
    Result = Data.define(:success?, :action, :prompt, :version, :errors)

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
        can_update_existing_version? ? update_existing_version : create_new_version
      else
        create_new_prompt
      end
    end

    private

    attr_reader :params, :prompt, :prompt_version

    def can_update_existing_version?
      params[:save_action] == "update" &&
        prompt_version.present? &&
        !prompt_version.has_responses?
    end

    def update_existing_version
      if prompt_version.update(version_attributes)
        success_result(:updated, prompt, prompt_version)
      else
        failure_result(prompt_version.errors.full_messages)
      end
    end

    def create_new_version
      version = prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

      if version.save
        success_result(:created, prompt, version)
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
        success_result(:created, new_prompt, version)
      else
        failure_result(new_prompt.errors.full_messages + version.errors.full_messages)
      end
    end

    def version_attributes
      {
        user_prompt: params[:user_prompt],
        system_prompt: params[:system_prompt],
        notes: params[:notes],
        model_config: params[:model_config] || {},
        response_schema: params[:response_schema]
      }
    end

    def success_result(action, prompt, version)
      Result.new(success?: true, action: action, prompt: prompt, version: version, errors: [])
    end

    def failure_result(errors)
      Result.new(success?: false, action: nil, prompt: nil, version: nil, errors: errors)
    end
  end
end
