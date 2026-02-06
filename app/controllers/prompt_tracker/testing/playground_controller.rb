# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for the interactive prompt playground in the Testing section.
    # Allows users to draft and test prompt templates with live preview.
    # Can be used standalone or in the context of an existing prompt.
    class PlaygroundController < ApplicationController
    before_action :set_prompt, if: -> { params[:prompt_id].present? }
    before_action :set_prompt_version, if: -> { params[:prompt_version_id].present? }
    before_action :set_version, only: [ :show ]

    # GET /playground (standalone)
    # GET /prompts/:prompt_id/playground (edit existing prompt - uses active/latest version)
    # GET /prompts/:prompt_id/versions/:prompt_version_id/playground (edit specific version)
    # Show the playground interface
    def show
      if @prompt_version
        # Version-specific playground
        @prompt = @prompt_version.prompt
        @version = @prompt_version
        @variables = extract_variables_from_both_prompts(@version.system_prompt, @version.user_prompt)
      elsif @prompt
        # Prompt-level playground (shortcut to active/latest version)
        @version = @prompt.active_version || @prompt.latest_version
        @variables = extract_variables_from_both_prompts(@version&.system_prompt || "", @version&.user_prompt || "")
      else
        # Standalone playground
        @version = nil
        @variables = []
      end

      @sample_variables = build_sample_variables(@variables)
      @available_providers = helpers.providers_for(:playground)
    end

    # POST /prompts/:prompt_id/playground/preview
    # POST /playground/preview
    # Preview both system_prompt and user_prompt with given variables
    def preview
      system_prompt = params[:system_prompt] || ""
      user_prompt = params[:user_prompt]
      # Convert ActionController::Parameters to hash
      variables = params[:variables]&.to_unsafe_h || {}

      # Handle empty user_prompt
      if user_prompt.blank?
        render json: {
          success: false,
          errors: [ "User prompt cannot be empty" ]
        }, status: :unprocessable_entity
        return
      end

      # Render system prompt if present
      rendered_system = nil
      if system_prompt.present?
        system_renderer = TemplateRenderer.new(system_prompt)
        rendered_system = system_renderer.render(variables)
      end

      # Render user prompt
      user_renderer = TemplateRenderer.new(user_prompt)
      rendered_user = user_renderer.render(variables)
      is_liquid = user_renderer.liquid_template?

      render json: {
        success: true,
        rendered_system: rendered_system,
        rendered_user: rendered_user,
        engine: is_liquid ? "liquid" : "mustache",
        variables_detected: extract_variables_from_both_prompts(system_prompt, user_prompt)
      }
    rescue Liquid::SyntaxError => e
      render json: {
        success: false,
        errors: [ "Liquid syntax error: #{e.message}" ]
      }, status: :unprocessable_entity
    end

    # POST /playground/generate
    # POST /prompts/:prompt_id/playground/generate
    # POST /prompts/:prompt_id/versions/:prompt_version_id/playground/generate
    # Generate prompts from scratch based on a description
    def generate
      description = params[:description]

      result = PromptGeneratorService.generate(description: description)

      render json: {
        success: true,
        system_prompt: result[:system_prompt],
        user_prompt: result[:user_prompt],
        variables: result[:variables],
        explanation: result[:explanation]
      }
    rescue => e
      Rails.logger.error("Prompt generation failed: #{e.message}")
      render json: {
        success: false,
        error: "Generation failed: #{e.message}"
      }, status: :unprocessable_entity
    end

    # POST /playground/save (standalone - creates new prompt)
    # POST /prompts/:prompt_id/playground/save (creates new version or updates existing)
    # POST /prompts/:prompt_id/versions/:prompt_version_id/playground/save (updates specific version or creates new)
    # Save the user_prompt as a new draft version, update existing version, or new prompt
    def save
      result = PlaygroundSaveService.call(
        params: save_params,
        prompt: @prompt,
        prompt_version: @prompt_version
      )

      if result.success?
        render json: build_success_response(result)
      else
        render json: { success: false, errors: result.errors }, status: :unprocessable_entity
      end
    end

    # POST /playground/execute
    # POST /prompts/:prompt_id/playground/execute
    # POST /prompts/:prompt_id/versions/:prompt_version_id/playground/execute
    # Execute a Response API call with conversation support
    def execute
      result = PlaygroundExecuteService.call(
        content: params[:content],
        system_prompt: params[:system_prompt],
        user_prompt_template: params[:user_prompt],
        model_config: params[:model_config]&.to_unsafe_h || {},
        conversation_state: conversation_state,
        variables: params[:variables]&.to_unsafe_h || {}
      )

      if result.success?
        # Update session with new conversation state
        update_conversation_state(result.conversation_state)

        render json: {
          success: true,
          message: {
            content: result.content,
            tools_used: result.tools_used
          },
          usage: result.usage
        }
      else
        render json: { success: false, error: result.error }, status: :unprocessable_entity
      end
    end

    # POST /playground/reset_conversation
    # POST /prompts/:prompt_id/playground/reset_conversation
    # POST /prompts/:prompt_id/versions/:prompt_version_id/playground/reset_conversation
    # Reset the conversation state
    def reset_conversation
      clear_conversation_state

      render json: { success: true }
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:prompt_id])
    end

    def set_prompt_version
      @prompt_version = PromptVersion.find(params[:prompt_version_id])
    end

    def set_version
      if params[:version_id]
        @version = @prompt.prompt_versions.find(params[:version_id])
      end
    end

    def save_params
      @save_params ||= params.permit(
        :user_prompt, :system_prompt, :notes, :prompt_name,
        :prompt_slug, :save_action
      ).to_h.with_indifferent_access.merge(
        model_config: params[:model_config]&.to_unsafe_h || {},
        response_schema: extract_response_schema_param
      )
    end

    def extract_response_schema_param
      schema_param = params[:response_schema]
      return nil if schema_param.blank?

      schema_param.respond_to?(:to_unsafe_h) ? schema_param.to_unsafe_h : schema_param
    end

    def build_success_response(result)
      response = {
        success: true,
        version_id: result.version.id,
        version_number: result.version.version_number,
        redirect_url: testing_prompt_prompt_version_path(result.prompt, result.version),
        action: result.action.to_s
      }
      response[:prompt_id] = result.prompt.id if result.action == :created && @prompt.nil?
      response
    end

    # Extract variable names from both system and user prompts
    # Combines variables from both and returns unique sorted list
    def extract_variables_from_both_prompts(system_prompt, user_prompt)
      system_vars = extract_variables_from_template(system_prompt || "")
      user_vars = extract_variables_from_template(user_prompt || "")
      (system_vars + user_vars).uniq.sort
    end

    # Extract variable names from template
    # Supports both {{variable}} and {{ variable }} syntax
    def extract_variables_from_template(template)
      return [] if template.blank?

      variables = []

      # Extract Mustache-style variables: {{variable}}
      variables += template.scan(/\{\{\s*(\w+)\s*\}\}/).flatten

      # Extract Liquid variables with filters: {{ variable | filter }}
      variables += template.scan(/\{\{\s*(\w+)\s*\|/).flatten

      # Extract Liquid object notation: {{ object.property }}
      variables += template.scan(/\{\{\s*(\w+)\./).flatten

      # Extract from conditionals: {% if variable %}
      variables += template.scan(/\{%\s*if\s+(\w+)/).flatten

      # Extract from loops: {% for item in items %}
      variables += template.scan(/\{%\s*for\s+\w+\s+in\s+(\w+)/).flatten

      variables.uniq.sort
    end

    # Build sample variables hash with empty strings
    def build_sample_variables(variable_names)
      variable_names.each_with_object({}) do |name, hash|
        hash[name] = ""
      end
    end

    # Get conversation state from session
    # Uses a unique key based on prompt/version context
    def conversation_state
      session[conversation_session_key] || {
        "messages" => [],
        "previous_response_id" => nil,
        "started_at" => nil
      }
    end

    # Update conversation state in session
    def update_conversation_state(state)
      session[conversation_session_key] = state
    end

    # Clear conversation state from session
    def clear_conversation_state
      session.delete(conversation_session_key)
    end

    # Generate unique session key for conversation state
    def conversation_session_key
      base_key = "playground_conversation"
      if @prompt_version
        "#{base_key}_version_#{@prompt_version.id}"
      elsif @prompt
        "#{base_key}_prompt_#{@prompt.id}"
      else
        "#{base_key}_standalone"
      end
    end
    end
  end
end
