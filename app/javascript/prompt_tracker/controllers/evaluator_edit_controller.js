import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Evaluator Edit Stimulus Controller
 * Handles opening and submitting the edit evaluator modal
 */
export default class extends Controller {
  static values = {
    configId: Number,
    promptId: Number
  }

  /**
   * Open the edit modal and load the evaluator config data
   */
  open(event) {
    event.preventDefault()

    const configId = this.configIdValue
    const promptId = this.promptIdValue

    // Fetch the evaluator config data
    fetch(`/prompt_tracker/prompts/${promptId}/evaluators/${configId}.json`)
      .then(response => {
        if (!response.ok) {
          throw new Error('Failed to fetch evaluator config')
        }
        return response.json()
      })
      .then(config => {
        this.populateModal(config)
        this.showModal()
      })
      .catch(error => {
        console.error('Error fetching evaluator config:', error)
        alert('Failed to load evaluator configuration')
      })
  }

  /**
   * Populate the modal fields with config data
   */
  populateModal(config) {
    document.getElementById('edit_evaluator_id').value = config.id
    // Use evaluator_name for display (human-readable), evaluator_key for hidden field
    document.getElementById('edit_evaluator_key_display').value = config.evaluator_name || config.evaluator_key
    document.getElementById('edit_evaluator_key_hidden').value = config.evaluator_key
    document.getElementById('edit_enabled').checked = config.enabled

    // Load the dynamic form for this evaluator with existing config
    this.loadConfigForm(config.evaluator_key, config.id)
  }

  /**
   * Load the configuration form for the evaluator
   */
  loadConfigForm(evaluatorKey, configId) {
    const frame = document.getElementById('edit_evaluator_config_container')
    if (!frame) return

    const params = new URLSearchParams({
      evaluator_key: evaluatorKey,
      config_id: configId
    })

    const url = `/prompt_tracker/evaluator_configs/config_form?${params.toString()}`
    frame.src = url
  }

  /**
   * Show the modal using Bootstrap 5 API
   */
  showModal() {
    const modalElement = document.getElementById('editEvaluatorModal')
    const modal = new Modal(modalElement)
    modal.show()
  }
}
