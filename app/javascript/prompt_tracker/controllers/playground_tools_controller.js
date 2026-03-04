import { Controller } from "@hotwired/stimulus"

/**
 * Playground Tools Controller
 *
 * Single Responsibility: Manage tool selection state and configuration panel visibility
 *
 * This controller handles:
 * - Tool checkbox state changes (visual active/inactive state)
 * - Show/hide configuration panels based on checkbox state
 * - Dynamic tool card rendering when provider/API changes
 */
export default class extends Controller {
  static targets = [
    "toolCheckbox",      // All tool checkboxes
    "toolCardsContainer", // Container for tool cards (for dynamic updates)
    "fileSearchPanel",   // File search config panel
    "functionsPanel"     // Functions config panel
  ]

  connect() {
    // Defer initial update to ensure DOM is fully ready
    requestAnimationFrame(() => {
      this.initializeToolCardStates()
      this.updatePanelVisibility()
    })
  }

  /**
   * Initialize tool card states on page load
   * Apply 'active' class to cards with checked checkboxes
   */
  initializeToolCardStates() {
    const checkboxes = this.getCheckboxes()
    checkboxes.forEach(checkbox => {
      if (checkbox.checked) {
        this.updateToolCardState(checkbox)
      }
    })
  }

  /**
   * Update the available tools when provider/API changes
   * Called by playground_ui_controller via outlet
   *
   * @param {Array<Object>} tools - Array of tool objects with id, name, description, icon, configurable
   */
  updateTools(tools) {
    if (!this.hasToolCardsContainerTarget) {
      console.warn('[PlaygroundToolsController] No tool cards container target found')
      return
    }

    console.log(`[PlaygroundToolsController] Updating tools:`, tools)

    // Save current checked state before clearing
    const currentState = {}
    this.getCheckboxes().forEach(checkbox => {
      currentState[checkbox.dataset.toolId] = checkbox.checked
    })

    // Clear existing tool cards
    this.toolCardsContainerTarget.innerHTML = ''

    // Render new tool cards
    if (tools && tools.length > 0) {
      tools.forEach(tool => {
        const cardHtml = this.buildToolCardHtml(tool, currentState[tool.id] || false)
        this.toolCardsContainerTarget.insertAdjacentHTML('beforeend', cardHtml)
      })

      // Restore active state for checked tools
      requestAnimationFrame(() => {
        this.getCheckboxes().forEach(checkbox => {
          if (checkbox.checked) {
            this.updateToolCardState(checkbox)
          }
        })
        this.updatePanelVisibility()
      })
    } else {
      // Show "no tools" message
      this.toolCardsContainerTarget.innerHTML = `
        <div class="col-12">
          <div class="alert alert-secondary py-2 mb-0">
            <i class="bi bi-info-circle"></i>
            No tools available for this API.
          </div>
        </div>
      `
      this.updatePanelVisibility()
    }
  }

  /**
   * Build HTML for a single tool card
   * @param {Object} tool - Tool object with id, name, description, icon, configurable
   * @param {boolean} isChecked - Whether the checkbox should be checked
   * @returns {string} HTML string for the tool card
   * @private
   */
  buildToolCardHtml(tool, isChecked = false) {
    const checkboxId = `tool_${tool.id}`
    const configurable = tool.configurable === true
    const checkedAttr = isChecked ? 'checked' : ''

    return `
      <div class="col-md-3">
        <label class="card tool-card p-3 h-100 position-relative"
               for="${checkboxId}">
          <input class="d-none"
                 type="checkbox"
                 id="${checkboxId}"
                 value="${tool.id}"
                 data-playground-tools-target="toolCheckbox"
                 data-tool-id="${tool.id}"
                 data-configurable="${configurable}"
                 data-action="change->playground-tools#onToolToggle"
                 ${checkedAttr}>
          <i class="bi bi-check-circle-fill check-indicator"></i>
          <div class="text-center">
            <i class="bi ${tool.icon} tool-icon d-block mb-2"></i>
            <strong class="d-block" style="font-size: 0.85rem;">${tool.name}</strong>
            <small class="text-muted" style="font-size: 0.7rem;">${tool.description}</small>
          </div>
        </label>
      </div>
    `
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
