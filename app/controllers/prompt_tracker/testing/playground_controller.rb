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
      if @prompt
        if can_update_existing_version?
          update_existing_version
        else
          create_new_version
        end
      else
        create_new_prompt
      end
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

    def can_update_existing_version?
      save_params[:save_action] == "update" &&
        @prompt_version.present? &&
        !@prompt_version.has_responses?
    end

    def update_existing_version
      if @prompt_version.update(version_attributes)
        render json: {
          success: true,
          version_id: @prompt_version.id,
          version_number: @prompt_version.version_number,
          redirect_url: testing_prompt_prompt_version_path(@prompt, @prompt_version),
          action: "updated"
        }
      else
        render json: {
          success: false,
          errors: @prompt_version.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def create_new_version
      version = @prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

      if version.save
        render json: {
          success: true,
          version_id: version.id,
          version_number: version.version_number,
          redirect_url: testing_prompt_prompt_version_path(@prompt, version),
          action: "created"
        }
      else
        render json: {
          success: false,
          errors: version.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def create_new_prompt
      if save_params[:prompt_name].blank?
        render json: {
          success: false,
          errors: [ "Prompt name is required" ]
        }, status: :unprocessable_entity
        return
      end

      prompt = Prompt.new(
        name: save_params[:prompt_name],
        slug: save_params[:prompt_slug].presence,
        description: save_params[:notes]
      )

      version = prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

      if prompt.save
        render json: {
          success: true,
          prompt_id: prompt.id,
          version_id: version.id,
          version_number: version.version_number,
          redirect_url: testing_prompt_prompt_version_path(prompt, version)
        }
      else
        render json: {
          success: false,
          errors: prompt.errors.full_messages + version.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def version_attributes
      {
        user_prompt: save_params[:user_prompt],
        system_prompt: save_params[:system_prompt],
        notes: save_params[:notes],
        model_config: save_params[:model_config],
        response_schema: save_params[:response_schema]
      }
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
    end
  end
end
