import { Controller } from "@hotwired/stimulus"

/**
 * Evaluator Configs Stimulus Controller
 *
 * Manages evaluator selection, configuration forms, and syncs to a single hidden JSON field.
 * Uses in-memory state (this.configs) instead of per-evaluator hidden fields.
 *
 * Architecture:
 * - this.configs: Object storing config for each evaluator key { evaluator_key: { config } }
 * - hiddenFieldTarget: Single hidden field storing the final JSON array for form submission
 * - Form inputs trigger syncEvaluatorConfig() which updates this.configs and then updateJson()
 */
export default class extends Controller {
  static targets = ["checkbox", "config", "hiddenField", "configFormContainer"]

  connect() {
    console.log('[EvaluatorConfigs] Controller connected')
    console.log('[EvaluatorConfigs] Targets found:', {
      checkboxes: this.checkboxTargets.length,
      configs: this.configTargets.length,
      hiddenField: this.hasHiddenFieldTarget,
      configFormContainers: this.configFormContainerTargets.length
    })

    // Initialize in-memory config state from existing hidden field value
    this.initializeConfigsFromHiddenField()

    this.attachEventListeners()
    this.initializeRequiredFields()

    // Initial sync of all evaluator configs from form inputs
    this.syncAllEvaluatorConfigs()
  }

  /**
   * Initialize this.configs from the existing hidden field value (for edit forms)
   */
  initializeConfigsFromHiddenField() {
    this.configs = {}

    if (this.hasHiddenFieldTarget && this.hiddenFieldTarget.value) {
      try {
        const existingConfigs = JSON.parse(this.hiddenFieldTarget.value)
        if (Array.isArray(existingConfigs)) {
          existingConfigs.forEach(item => {
            if (item.evaluator_key && item.config) {
              this.configs[item.evaluator_key] = item.config
            }
          })
        }
        console.log('[EvaluatorConfigs] Initialized configs from hidden field:', this.configs)
      } catch (e) {
        console.warn('[EvaluatorConfigs] Could not parse existing hidden field value:', e)
      }
    }
  }

  /**
   * Sync all evaluator configs from form inputs on initial load
   */
  syncAllEvaluatorConfigs() {
    this.configFormContainerTargets.forEach(container => {
      const evaluatorKey = container.dataset.evaluatorKey
      this.collectConfigFromContainer(evaluatorKey, container)
    })
    this.updateJson()
  }

  /**
   * Initialize required fields state based on checkbox state
   * Disable required fields for unchecked evaluators on page load
   */
  initializeRequiredFields() {
    console.log('[EvaluatorConfigs] Initializing required fields')
    this.checkboxTargets.forEach(checkbox => {
      const key = checkbox.dataset.evaluatorKey
      const configDiv = this.configTargets.find(
        target => target.id === `config_${key}`
      )

      if (configDiv) {
        // Disable required fields if evaluator is not checked
        this.setRequiredFields(configDiv, checkbox.checked)
        console.log(`[EvaluatorConfigs] Evaluator "${key}" - checked: ${checkbox.checked}`)
      }
    })
  }

  /**
   * Attach event listeners to all config form inputs
   * Forms are now rendered server-side, so we just need to attach listeners
   */
  attachEventListeners() {
    console.log('[EvaluatorConfigs] Attaching event listeners')
    this.configFormContainerTargets.forEach(container => {
      const evaluatorKey = container.dataset.evaluatorKey
      console.log(`[EvaluatorConfigs] Processing container for evaluator: ${evaluatorKey}`)

      // Add event listeners to all form inputs to sync with hidden field
      // Exclude checkboxes inside checkbox-group containers (handled separately)
      let inputCount = 0
      let skippedCount = 0
      container.querySelectorAll('input, select, textarea').forEach(input => {
        // Skip checkboxes that are part of a checkbox-group (they trigger syncCheckboxGroup)
        if (input.closest('[data-config-checkbox-group]')) {
          skippedCount++
          return
        }

        inputCount++
        input.addEventListener('change', () => this.syncEvaluatorConfig(evaluatorKey))
        input.addEventListener('input', () => this.syncEvaluatorConfig(evaluatorKey))
      })
      console.log(`[EvaluatorConfigs] Evaluator "${evaluatorKey}": attached listeners to ${inputCount} inputs, skipped ${skippedCount} (in checkbox groups)`)

      // Log checkbox groups found
      const checkboxGroups = container.querySelectorAll('[data-config-checkbox-group]')
      if (checkboxGroups.length > 0) {
        checkboxGroups.forEach(group => {
          const fieldName = group.dataset.configCheckboxGroup
          const checkboxCount = group.querySelectorAll('input[type="checkbox"]').length
          console.log(`[EvaluatorConfigs] Found checkbox group "${fieldName}" with ${checkboxCount} checkboxes`)
        })
      }
    })
  }

  /**
   * Collect config values from a container and store in this.configs
   */
  collectConfigFromContainer(evaluatorKey, container) {
    const config = {}

    // 1. Collect values from regular form inputs with name="config[...]"
    container.querySelectorAll('[name^="config["]').forEach(input => {
      const match = input.name.match(/config\[([^\]]+)\]/)
      if (!match) return

      const key = match[1]

      if (input.type === 'checkbox') {
        // Skip if this checkbox is inside a checkbox-group (handled below)
        if (input.closest('[data-config-checkbox-group]')) return
        config[key] = input.checked
      } else if (input.tagName === 'SELECT' && input.multiple) {
        config[key] = Array.from(input.selectedOptions).map(opt => opt.value)
      } else if (input.type === 'number') {
        config[key] = parseFloat(input.value) || 0
      } else if (key === 'patterns' || key === 'required_keywords' || key === 'forbidden_keywords' || key === 'expected_functions') {
        // Convert textarea input (one item per line) to array
        config[key] = input.value.split('\n').map(line => line.trim()).filter(line => line.length > 0)
      } else {
        config[key] = input.value
      }
    })

    // 2. Collect values from checkbox groups (data-config-checkbox-group="fieldName")
    container.querySelectorAll('[data-config-checkbox-group]').forEach(group => {
      const fieldName = group.dataset.configCheckboxGroup
      const selectedValues = []

      group.querySelectorAll('input[type="checkbox"]:checked').forEach(cb => {
        selectedValues.push(cb.value)
      })

      config[fieldName] = selectedValues
    })

    this.configs[evaluatorKey] = config
    return config
  }

  /**
   * Sync evaluator configuration from form to in-memory state and hidden field
   */
  syncEvaluatorConfig(evaluatorKey) {
    console.log(`[EvaluatorConfigs] syncEvaluatorConfig called for: ${evaluatorKey}`)

    const container = this.configFormContainerTargets.find(
      c => c.dataset.evaluatorKey === evaluatorKey
    )

    if (!container) {
      console.warn(`[EvaluatorConfigs] No container found for evaluator: ${evaluatorKey}`)
      return
    }

    const config = this.collectConfigFromContainer(evaluatorKey, container)
    console.log(`[EvaluatorConfigs] Collected config for "${evaluatorKey}":`, config)

    this.updateJson()
  }

  /**
   * Handle checkbox changes within a checkbox group
   * Called via data-action="change->evaluator-configs#syncCheckboxGroup"
   */
  syncCheckboxGroup(event) {
    console.log('[EvaluatorConfigs] syncCheckboxGroup called')
    console.log('[EvaluatorConfigs] Checkbox value:', event.target.value, 'checked:', event.target.checked)

    // Find the evaluator key from the configFormContainer
    const container = event.target.closest('[data-evaluator-configs-target="configFormContainer"]')
    if (!container) {
      console.warn('[EvaluatorConfigs] Could not find configFormContainer parent!')
      return
    }

    const evaluatorKey = container.dataset.evaluatorKey
    console.log(`[EvaluatorConfigs] Found container for evaluator: ${evaluatorKey}`)
    this.syncEvaluatorConfig(evaluatorKey)
  }

  /**
   * Toggle evaluator config visibility when checkbox changes
   */
  toggleConfig(event) {
    const checkbox = event.target
    const key = checkbox.dataset.evaluatorKey
    console.log(`[EvaluatorConfigs] toggleConfig called for: ${key}, checked: ${checkbox.checked}`)

    const configDiv = this.configTargets.find(
      target => target.id === `config_${key}`
    )

    if (configDiv) {
      if (checkbox.checked) {
        console.log(`[EvaluatorConfigs] Expanding config section for: ${key}`)
        configDiv.classList.remove('collapse')
        // Enable all required fields when evaluator is selected
        this.setRequiredFields(configDiv, true)
      } else {
        console.log(`[EvaluatorConfigs] Collapsing config section for: ${key}`)
        configDiv.classList.add('collapse')
        // Disable all required fields when evaluator is unchecked
        this.setRequiredFields(configDiv, false)
      }
    } else {
      console.warn(`[EvaluatorConfigs] No config section found for: ${key}`)
    }

    this.updateJson()
  }

  /**
   * Enable or disable required fields in a config section
   * Disabled fields are ignored by HTML5 form validation
   */
  setRequiredFields(container, enabled) {
    const requiredFields = container.querySelectorAll('[required]')
    console.log(`[EvaluatorConfigs] setRequiredFields: ${enabled ? 'enabling' : 'disabling'} ${requiredFields.length} required fields`)

    requiredFields.forEach(field => {
      if (enabled) {
        field.removeAttribute('disabled')
      } else {
        field.setAttribute('disabled', 'disabled')
      }
    })
  }

  /**
   * Update the hidden JSON field with all selected evaluator configurations
   * Uses in-memory this.configs state instead of per-evaluator hidden fields
   */
  updateJson() {
    console.log('[EvaluatorConfigs] updateJson called')
    const configs = []

    this.checkboxTargets.forEach(checkbox => {
      if (!checkbox.checked) {
        console.log(`[EvaluatorConfigs] Skipping unchecked evaluator: ${checkbox.dataset.evaluatorKey}`)
        return
      }

      const key = checkbox.dataset.evaluatorKey
      const config = this.configs[key] || {}

      console.log(`[EvaluatorConfigs] Including config for "${key}":`, config)

      configs.push({
        evaluator_key: key,
        config: config
      })
    })

    const jsonValue = JSON.stringify(configs)
    console.log('[EvaluatorConfigs] Final evaluator_configs JSON:', jsonValue)
    console.log('[EvaluatorConfigs] Parsed for readability:', configs)
    this.hiddenFieldTarget.value = jsonValue
  }
}
