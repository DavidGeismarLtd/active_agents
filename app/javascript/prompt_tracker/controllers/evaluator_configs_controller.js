import { Controller } from "@hotwired/stimulus"

/**
 * Evaluator Configs Stimulus Controller
 * Manages evaluator selection, configuration forms, and syncs to a hidden JSON field
 */
export default class extends Controller {
  static targets = ["checkbox", "config", "configJson", "hiddenField", "configFormContainer"]

  connect() {
    this.attachEventListeners()
    this.initializeRequiredFields()
    this.updateJson()
  }

  /**
   * Initialize required fields state based on checkbox state
   * Disable required fields for unchecked evaluators on page load
   */
  initializeRequiredFields() {
    this.checkboxTargets.forEach(checkbox => {
      const key = checkbox.dataset.evaluatorKey
      const configDiv = this.configTargets.find(
        target => target.id === `config_${key}`
      )

      if (configDiv) {
        // Disable required fields if evaluator is not checked
        this.setRequiredFields(configDiv, checkbox.checked)
      }
    })
  }

  /**
   * Attach event listeners to all config form inputs
   * Forms are now rendered server-side, so we just need to attach listeners
   */
  attachEventListeners() {
    this.configFormContainerTargets.forEach(container => {
      const evaluatorKey = container.dataset.evaluatorKey

      // Add event listeners to all form inputs to sync with hidden field
      container.querySelectorAll('input, select, textarea').forEach(input => {
        input.addEventListener('change', () => this.syncEvaluatorConfig(evaluatorKey))
        input.addEventListener('input', () => this.syncEvaluatorConfig(evaluatorKey))
      })
    })
  }

  /**
   * Sync evaluator configuration from form to hidden field
   */
  syncEvaluatorConfig(evaluatorKey) {
    const container = this.configFormContainerTargets.find(
      c => c.dataset.evaluatorKey === evaluatorKey
    )
    const hiddenField = this.configJsonTargets.find(
      field => field.dataset.evaluatorKey === evaluatorKey
    )

    if (!container || !hiddenField) return

    const config = {}

    // Collect all form values
    container.querySelectorAll('[name^="config["]').forEach(input => {
      const match = input.name.match(/config\[([^\]]+)\]/)
      if (!match) return

      const key = match[1]

      if (input.type === 'checkbox') {
        config[key] = input.checked
      } else if (input.tagName === 'SELECT' && input.multiple) {
        // Handle multi-select
        config[key] = Array.from(input.selectedOptions).map(opt => opt.value)
      } else if (input.type === 'number') {
        config[key] = parseFloat(input.value) || 0
      } else if (key === 'patterns' || key === 'required_keywords' || key === 'forbidden_keywords' || key === 'expected_functions' || key === 'expected_files') {
        // Convert textarea/hidden field input (one item per line) to array
        config[key] = input.value.split('\n').map(line => line.trim()).filter(line => line.length > 0)
      } else {
        config[key] = input.value
      }
    })

    hiddenField.value = JSON.stringify(config)
    this.updateJson()
  }

  /**
   * Toggle evaluator config visibility when checkbox changes
   */
  toggleConfig(event) {
    const checkbox = event.target
    const key = checkbox.dataset.evaluatorKey
    const configDiv = this.configTargets.find(
      target => target.id === `config_${key}`
    )

    if (configDiv) {
      if (checkbox.checked) {
        configDiv.classList.remove('collapse')
        // Enable all required fields when evaluator is selected
        this.setRequiredFields(configDiv, true)
      } else {
        configDiv.classList.add('collapse')
        // Disable all required fields when evaluator is unchecked
        this.setRequiredFields(configDiv, false)
      }
    }

    this.updateJson()
  }

  /**
   * Enable or disable required fields in a config section
   * Disabled fields are ignored by HTML5 form validation
   */
  setRequiredFields(container, enabled) {
    container.querySelectorAll('[required]').forEach(field => {
      if (enabled) {
        field.removeAttribute('disabled')
      } else {
        field.setAttribute('disabled', 'disabled')
      }
    })
  }

  /**
   * Update the hidden JSON field with all selected evaluator configurations
   */
  updateJson() {
    const configs = []

    this.checkboxTargets.forEach(checkbox => {
      if (!checkbox.checked) return

      const key = checkbox.dataset.evaluatorKey
      const configHiddenField = this.configJsonTargets.find(
        field => field.dataset.evaluatorKey === key
      )

      let config = {}
      if (configHiddenField && configHiddenField.value) {
        try {
          config = JSON.parse(configHiddenField.value)
        } catch (e) {
          config = {}
        }
      }

      configs.push({
        evaluator_key: key,
        config: config
      })
    })

    this.hiddenFieldTarget.value = JSON.stringify(configs)
  }
}
