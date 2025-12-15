import { Controller } from "@hotwired/stimulus"

/**
 * Evaluator Config Form Stimulus Controller
 * Handles dynamic loading of evaluator configuration forms in the Add Evaluator modal
 */
export default class extends Controller {
  static targets = ["select", "description"]
  static values = {
    promptId: Number,
    versionId: Number
  }

  /**
   * Load the appropriate configuration form when evaluator is selected
   */
  loadForm(event) {
    const selectedOption = this.selectTarget.options[this.selectTarget.selectedIndex]
    const evaluatorKey = selectedOption.value

    const frame = document.getElementById("evaluator_config_container")
    if (!frame) return

    if (!evaluatorKey) {
      // Reset to empty state
      frame.innerHTML = `
        <div class="text-center py-4 text-muted">
          <i class="bi bi-arrow-up"></i>
          <p>Select an evaluator above to configure it</p>
        </div>
      `
      this.descriptionTarget.innerHTML = ''
      return
    }

    // Show evaluator description
    this.showDescription(evaluatorKey)

    // Build the URL for the configuration form
    const url = this.buildFormUrl(evaluatorKey)

    // Set the frame's src attribute to trigger Turbo Frame navigation
    frame.src = url
  }

  /**
   * Show evaluator description from registry
   */
  showDescription(evaluatorKey) {
    // Get evaluator metadata from the data attribute
    const evaluators = JSON.parse(this.selectTarget.dataset.evaluators || '{}')
    const evaluator = evaluators[evaluatorKey]

    if (evaluator) {
      this.descriptionTarget.innerHTML = `
        <div class="alert alert-info">
          <strong>${evaluator.name}</strong><br>
          ${evaluator.description}<br>
          <small class="text-muted">Category: ${evaluator.category}</small>
        </div>
      `
    } else {
      this.descriptionTarget.innerHTML = ''
    }
  }

  /**
   * Build the URL for fetching the configuration form template
   */
  buildFormUrl(evaluatorKey) {
    const params = new URLSearchParams({
      evaluator_key: evaluatorKey
    })

    return `/prompt_tracker/evaluator_configs/config_form?${params.toString()}`
  }
}
