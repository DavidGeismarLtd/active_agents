# frozen_string_literal: true

module PromptTracker
  # Helper methods for evaluator configuration views.
  #
  # Extracts complex Ruby logic from ERB templates into testable helper methods.
  # This keeps views clean and focused on presentation.
  module EvaluatorConfigsHelper
    # Data structure for evaluator form state
    EvaluatorFormData = Struct.new(
      :all_evaluators,
      :current_evaluators,
      :has_vector_store,
      keyword_init: true
    )

    # Data structure for individual evaluator item state
    EvaluatorItemState = Struct.new(
      :key,
      :meta,
      :existing_config,
      :selected,
      :disabled,
      :disabled_reason,
      :default_config_json,
      keyword_init: true
    )

    # Build form data for evaluator configuration section
    #
    # @param test [PromptTracker::Test] The test being edited
    # @return [EvaluatorFormData] Data needed to render the evaluator form
    def evaluator_form_data(test)
      all_evaluators = PromptTracker::EvaluatorRegistry.all
      current_evaluators = test.evaluator_configs.to_a
      testable = test.testable

      # Check if testable has vector stores attached (for file_search evaluator)
      vector_store_ids = testable.model_config&.dig("tool_config", "file_search", "vector_store_ids") || []

      EvaluatorFormData.new(
        all_evaluators: all_evaluators,
        current_evaluators: current_evaluators,
        has_vector_store: vector_store_ids.present?
      )
    end

    # Build state for an individual evaluator item
    #
    # @param key [Symbol] The evaluator key
    # @param meta [Hash] The evaluator metadata from registry
    # @param form_data [EvaluatorFormData] The form data context
    # @return [EvaluatorItemState] State for rendering the evaluator item
    def evaluator_item_state(key, meta, form_data)
      existing_config = form_data.current_evaluators.find do |e|
        e.evaluator_type == meta[:evaluator_class].name
      end

      is_disabled = key.to_s == "file_search" && !form_data.has_vector_store
      disabled_reason = is_disabled ? "Attach a vector store to the assistant first" : nil

      # Build the default config JSON for the hidden field
      config_value = existing_config&.config || meta[:default_config] || {}

      EvaluatorItemState.new(
        key: key,
        meta: meta,
        existing_config: existing_config,
        selected: existing_config.present?,
        disabled: is_disabled,
        disabled_reason: disabled_reason,
        default_config_json: JSON.generate(config_value)
      )
    end

    # CSS classes for the evaluator card
    #
    # @param state [EvaluatorItemState] The evaluator item state
    # @return [String] CSS classes for the card
    def evaluator_card_classes(state)
      classes = [ "card", "h-100", "evaluator-item" ]
      classes << "border-primary" if state.selected
      classes << "opacity-50" if state.disabled
      classes.join(" ")
    end
  end
end
