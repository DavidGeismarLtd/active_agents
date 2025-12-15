# frozen_string_literal: true

module PromptTracker
  # Controller for managing evaluator configurations
  class EvaluatorConfigsController < ApplicationController
    before_action :set_prompt_and_version, except: [ :config_form ]
    before_action :set_evaluator_config, only: [ :show, :update, :destroy ]

    # GET /evaluator_configs/config_form
    # Returns the configuration form partial for a specific evaluator
    # Supports both add (new config) and edit (existing config) modes
    def config_form
      evaluator_key = params[:evaluator_key]
      config_id = params[:config_id]

      # Check if evaluator exists in registry
      unless EvaluatorRegistry.exists?(evaluator_key)
        render json: { error: "Evaluator '#{evaluator_key}' not found" }, status: :not_found
        return
      end

      # Fetch existing config if editing
      existing_config = config_id ? EvaluatorConfig.find_by(id: config_id) : nil

      # Try to render the specific form for this evaluator
      template_path = "prompt_tracker/evaluator_configs/forms/#{evaluator_key}"

      # Render the partial with existing_config and namespace available
      partial_content = render_to_string(
        partial: template_path,
        locals: {
          existing_config: existing_config,
          namespace: "evaluator_config[config]"
        }
      )

      # Use different frame ID for edit vs add
      frame_id = config_id ? "edit_evaluator_config_container" : "evaluator_config_container"

      render html: <<~HTML.html_safe, layout: false
        <turbo-frame id="#{frame_id}">
          #{partial_content}
        </turbo-frame>
      HTML
    rescue ActionView::MissingTemplate
      # If no custom form exists, return a message in turbo-frame
      frame_id = config_id ? "edit_evaluator_config_container" : "evaluator_config_container"
      render html: <<~HTML.html_safe, layout: false
        <turbo-frame id="#{frame_id}">
          <div class="alert alert-warning">
            <i class="bi bi-info-circle"></i>
            <strong>No custom configuration form available</strong>
            <p class="mb-0 mt-2">This evaluator will use default configuration values.</p>
          </div>
        </turbo-frame>
      HTML
    end

    # GET /prompts/:prompt_id/evaluators
    # List all evaluator configs for a prompt version (returns JSON for AJAX)
    def index
      @evaluator_configs = @version.evaluator_configs.order(:created_at)
      @available_evaluators = EvaluatorRegistry.all

      respond_to do |format|
        format.html { render partial: "evaluator_configs/list", locals: { prompt: @prompt, version: @version, evaluator_configs: @evaluator_configs } }
        format.json { render json: { configs: @evaluator_configs, available: @available_evaluators } }
      end
    end

    # GET /prompts/:prompt_id/evaluators/:id
    # Get a single evaluator config (for editing)
    def show
      respond_to do |format|
        format.json { render json: @evaluator_config }
      end
    end

    # POST /prompts/:prompt_id/evaluators
    # Create a new evaluator config for the active version
    def create
      # Process config params using evaluator class
      processed_params = evaluator_config_params
      processed_params[:config] = process_config_with_evaluator(processed_params) if processed_params[:config]

      @evaluator_config = @version.evaluator_configs.build(processed_params)

      if @evaluator_config.save
        respond_to do |format|
          format.html { redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators"), notice: "Evaluator configured successfully." }
          format.json { render json: @evaluator_config, status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators"), alert: "Failed to configure evaluator: #{@evaluator_config.errors.full_messages.join(', ')}" }
          format.json { render json: { errors: @evaluator_config.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /prompts/:prompt_id/evaluators/:id
    # Update an evaluator config
    def update
      # Process config params using evaluator class
      processed_params = evaluator_config_params
      if processed_params[:config]
        # Use the evaluator_key from params if provided, otherwise use the existing one
        evaluator_key = processed_params[:evaluator_key] || @evaluator_config.evaluator_key
        processed_params[:config] = process_config_with_evaluator(processed_params.merge(evaluator_key: evaluator_key))
      end

      if @evaluator_config.update(processed_params)
        respond_to do |format|
          format.html { redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators"), notice: "Evaluator updated successfully." }
          format.json { render json: @evaluator_config }
        end
      else
        respond_to do |format|
          format.html { redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators"), alert: "Failed to update evaluator: #{@evaluator_config.errors.full_messages.join(', ')}" }
          format.json { render json: { errors: @evaluator_config.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /prompts/:prompt_id/evaluators/:id
    # Delete an evaluator config
    def destroy
      @evaluator_config.destroy

      respond_to do |format|
        format.html { redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators"), notice: "Evaluator removed successfully." }
        format.json { head :no_content }
      end
    end

    # POST /prompts/:prompt_id/evaluators/copy_from_tests
    # Copy evaluator configs from tests to monitoring
    def copy_from_tests
      result = CopyTestEvaluatorsService.call(prompt_version: @version)

      if result.success?
        if result.copied_count > 0
          flash[:notice] = "Successfully copied #{result.copied_count} evaluator(s) from test config."
          flash[:notice] += " Skipped #{result.skipped_count} duplicate(s)." if result.skipped_count > 0
        else
          flash[:alert] = "No evaluators found in test config to copy."
        end
      else
        flash[:alert] = "Failed to copy evaluators: #{result.error}"
      end

      redirect_to monitoring_prompt_prompt_version_path(@prompt, @version, anchor: "auto-evaluators")
    end

    private

    def set_prompt_and_version
      @prompt = Prompt.find(params[:prompt_id])
      @version = @prompt.active_version

      unless @version
        respond_to do |format|
          format.json { render json: { error: "No active version" }, status: :unprocessable_entity }
        end
      end
    end

    def set_evaluator_config
      @evaluator_config = @version.evaluator_configs.find(params[:id])
    end

    def evaluator_config_params
      params.require(:evaluator_config).permit(
        :evaluator_key,
        :enabled,
        config: {}
      )
    end

    # Process config params by delegating to the evaluator class
    # Each evaluator class defines its own param_schema and handles type conversion
    #
    # @param params [Hash] the evaluator_config params including :evaluator_key and :config
    # @return [Hash] processed config hash with correct types
    def process_config_with_evaluator(params)
      evaluator_key = params[:evaluator_key]
      config_hash = params[:config]

      return {} if config_hash.blank?

      # Look up the evaluator class from the registry
      evaluator_metadata = EvaluatorRegistry.get(evaluator_key)

      if evaluator_metadata
        # Delegate to the evaluator class to process params
        evaluator_class = evaluator_metadata[:evaluator_class]
        evaluator_class.process_params(config_hash)
      else
        # Fallback: if evaluator not found in registry, return config as-is
        Rails.logger.warn("Evaluator '#{evaluator_key}' not found in registry, config params not processed")
        config_hash
      end
    end
  end
end
