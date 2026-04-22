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
      :testable,
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

    # Requirements for tool-based evaluators
    # Each entry defines:
    # - check: Lambda that returns true if the evaluator can be used
    # - reason: Message to display when the evaluator is disabled
    EVALUATOR_REQUIREMENTS = {
      file_search: {
        check: ->(testable) {
          testable.model_config&.dig("tool_config", "file_search", "vector_store_ids").present?
        },
        reason: "Attach a vector store to the assistant first"
      },
      function_call: {
        check: ->(testable) {
          tools = Array(testable.model_config&.dig("tools"))
          functions = testable.model_config&.dig("tool_config", "functions")
          tools.include?("functions") && functions.present?
        },
        reason: "Enable functions and define at least one function first"
      },
      web_search: {
        check: ->(testable) {
          Array(testable.model_config&.dig("tools")).include?("web_search")
        },
        reason: "Enable web search in the prompt version first"
      },
      code_interpreter: {
        check: ->(testable) {
          Array(testable.model_config&.dig("tools")).include?("code_interpreter")
        },
        reason: "Enable code interpreter in the prompt version first"
      }
    }.freeze

    # Serialize a test's existing evaluator_configs into the JSON shape
    # expected by evaluator_configs_controller.js#initializeConfigsFromHiddenField
    # (an array of { evaluator_key, config }). The association getter on Test
    # returns an AR::Associations::CollectionProxy, which Rails renders via
    # .to_s (= #<PromptTracker::...>) when fed directly to hidden_field — that
    # string is not valid JSON and makes the Stimulus controller skip prefill.
    #
    # Returns "[]" (not "") when there are no configs: if JS fails to rewrite
    # the hidden field before submit, tests_controller_base#test_params calls
    # JSON.parse on the raw string and an empty string would raise.
    #
    # @param test [PromptTracker::Test]
    # @return [String] JSON array string, "[]" when no configs exist
    def evaluator_configs_json_for(test)
      configs = Array(test.evaluator_configs)
      return "[]" if configs.empty?

      registry = PromptTracker::EvaluatorRegistry.all
      configs.map do |ec|
        entry = registry.find { |_key, meta| meta[:evaluator_class].name == ec.evaluator_type }
        next unless entry

        { evaluator_key: entry.first, config: ec.config || {} }
      end.compact.to_json
    end

    # Build form data for evaluator configuration section
    #
    # @param test [PromptTracker::Test] The test being edited
    # @return [EvaluatorFormData] Data needed to render the evaluator form
    def evaluator_form_data(test)
      all_evaluators = PromptTracker::EvaluatorRegistry.all
      current_evaluators = test.evaluator_configs.to_a
      testable = test.testable

      EvaluatorFormData.new(
        all_evaluators: all_evaluators,
        current_evaluators: current_evaluators,
        testable: testable
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

      is_disabled, disabled_reason = evaluator_disabled_state(key, form_data.testable)

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

    # Check if an evaluator should be disabled based on testable configuration
    #
    # @param key [Symbol] The evaluator key
    # @param testable [Object] The testable (AgentVersion, Assistant, etc.)
    # @return [Array<Boolean, String|nil>] [is_disabled, reason]
    def evaluator_disabled_state(key, testable)
      requirement = EVALUATOR_REQUIREMENTS[key.to_sym]
      return [ false, nil ] unless requirement

      is_enabled = requirement[:check].call(testable)
      is_enabled ? [ false, nil ] : [ true, requirement[:reason] ]
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
