import { Controller } from "@hotwired/stimulus"

/**
 * Playground Tools Controller
 *
 * Single Responsibility: Manage tool selection state and configuration panel visibility
 *
 * This controller handles:
 * - Tool checkbox state changes (visual active/inactive state)
 * - Show/hide configuration panels based on checkbox state
 */
export default class extends Controller {
  static targets = [
    "toolCheckbox",      // All tool checkboxes
    "fileSearchPanel",   // File search config panel
    "functionsPanel"     // Functions config panel
  ]

  connect() {
    // Defer initial update to ensure DOM is fully ready
    requestAnimationFrame(() => {
      this.updatePanelVisibility()
    })
  }

  /**
   * Handle tool checkbox toggle
   * @param {Event} event - Change event from checkbox
   */
  onToolToggle(event) {
    const checkbox = event.target
    const isConfigurable = checkbox.dataset.configurable === "true"

    // Update the visual state of the tool card
    this.updateToolCardState(checkbox)

    // Update panel visibility for configurable tools
    if (isConfigurable) {
      this.updatePanelVisibility()
    }
  }

  /**
   * Update the visual state of a tool card (active/inactive)
   * @param {HTMLInputElement} checkbox - The checkbox element
   */
  updateToolCardState(checkbox) {
    // The checkbox is inside a label.tool-card
    const toolCard = checkbox.closest(".tool-card")
    if (toolCard) {
      toolCard.classList.toggle("active", checkbox.checked)
    }
  }

  /**
   * Update visibility of configuration panels based on checkbox state
   */
  updatePanelVisibility() {
    const checkboxes = this.getCheckboxes()

    checkboxes.forEach(checkbox => {
      const toolId = checkbox.dataset.toolId

      if (toolId === "file_search" && this.hasFileSearchPanelTarget) {
        this.fileSearchPanelTarget.classList.toggle("show", checkbox.checked)
      }

      if (toolId === "functions" && this.hasFunctionsPanelTarget) {
        this.functionsPanelTarget.classList.toggle("show", checkbox.checked)
      }
    })
  }

  /**
   * Get array of selected tool IDs
   * @returns {Array<string>} Array of selected tool IDs
   */
  getSelectedTools() {
    return Array.from(this.getCheckboxes())
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.dataset.toolId)
  }

  /**
   * Get all tool checkboxes
   * @returns {NodeList|Array} Collection of checkbox elements
   * @private
   */
  getCheckboxes() {
    // Prefer Stimulus targets, fallback to DOM query
    if (this.toolCheckboxTargets.length > 0) {
      return this.toolCheckboxTargets
    }
    return this.element.querySelectorAll('input[type="checkbox"][data-tool-id]')
  }
}
