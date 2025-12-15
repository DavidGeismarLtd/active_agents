import { Controller } from "@hotwired/stimulus"

/**
 * Evaluator Edit Form Stimulus Controller
 * Handles form submission for editing evaluator configs
 */
export default class extends Controller {
  /**
   * Submit the edit form via AJAX
   */
  submit(event) {
    event.preventDefault()

    const configId = document.getElementById('edit_evaluator_id').value
    const promptId = document.getElementById('edit_prompt_id').value
    const enabled = document.getElementById('edit_enabled').checked

    // Extract config from form fields (not JSON textarea)
    const config = this.extractConfigFromForm()

    const formData = {
      evaluator_config: {
        enabled: enabled,
        config: config
      }
    }

    fetch(`/prompt_tracker/prompts/${promptId}/evaluators/${configId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify(formData)
    })
    .then(response => {
      if (response.ok) {
        window.location.reload()
      } else {
        return response.json().then(data => {
          throw new Error(data.errors ? data.errors.join(', ') : 'Failed to update evaluator configuration')
        })
      }
    })
    .catch(error => {
      console.error('Error updating evaluator config:', error)
      alert(error.message || 'Failed to update evaluator configuration')
    })
  }

  /**
   * Extract configuration from form fields
   * Looks for all inputs with name starting with "config["
   */
  extractConfigFromForm() {
    const form = document.getElementById('editEvaluatorForm')
    const formData = new FormData(form)
    const config = {}

    // Extract all config[...] fields
    for (let [key, value] of formData.entries()) {
      if (key.startsWith('config[')) {
        // Extract the config key name from "config[key_name]"
        const configKey = key.match(/config\[([^\]]+)\]/)[1]

        // Handle different value types
        if (value === 'true' || value === 'false') {
          config[configKey] = value === 'true'
        } else if (!isNaN(value) && value !== '') {
          config[configKey] = Number(value)
        } else {
          config[configKey] = value
        }
      }
    }

    return config
  }
}
