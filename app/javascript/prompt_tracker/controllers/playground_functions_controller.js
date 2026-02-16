import { Controller } from "@hotwired/stimulus"

/**
 * Playground Functions Controller
 * 
 * Single Responsibility: Manage custom functions configuration
 * 
 * This controller handles:
 * - Adding/removing function definitions
 * - Handling function field changes
 * - Serializing functions configuration
 * 
 * @fires playground-functions:configChanged - When functions config changes
 */
export default class extends Controller {
  static targets = [
    "functionsList",
    "functionItem",
    "noFunctionsMessage",
    "functionName",
    "functionDescription",
    "functionOutputDescription",
    "functionParameters",
    "functionStrict"
  ]

  /**
   * Add a new function definition
   */
  addFunction() {
    if (this.hasNoFunctionsMessageTarget) {
      this.noFunctionsMessageTarget.remove()
    }

    const index = this.functionItemTargets.length
    const template = this.createFunctionTemplate(index)
    this.functionsListTarget.insertAdjacentHTML("beforeend", template)
    this.dispatchConfigChange()
  }

  /**
   * Create HTML template for a new function item
   * @param {number} index - Function index
   * @returns {string} HTML template string
   */
  createFunctionTemplate(index) {
    return `
      <div class="function-item card mb-2" data-playground-functions-target="functionItem" data-function-index="${index}">
        <div class="card-body p-2">
          <div class="d-flex justify-content-between align-items-start mb-2">
            <div class="flex-grow-1 me-2">
              <input type="text"
                     class="form-control form-control-sm mb-1"
                     placeholder="Function name (e.g., get_weather)"
                     data-playground-functions-target="functionName"
                     data-action="input->playground-functions#onFunctionChange">
              <input type="text"
                     class="form-control form-control-sm mb-2"
                     placeholder="Description"
                     data-playground-functions-target="functionDescription"
                     data-action="input->playground-functions#onFunctionChange">
              <textarea class="form-control form-control-sm"
                        rows="2"
                        placeholder="Output description (e.g., Returns a JSON object with temperature, condition, and humidity fields)"
                        data-playground-functions-target="functionOutputDescription"
                        data-action="input->playground-functions#onFunctionChange"></textarea>
              <div class="form-text small">
                Describe what this function returns to help generate better mock outputs
              </div>
            </div>
            <button type="button"
                    class="btn btn-sm btn-outline-danger"
                    data-action="click->playground-functions#removeFunction">
              <i class="bi bi-trash"></i>
            </button>
          </div>

          <div class="mb-2">
            <label class="form-label small mb-1">Parameters (JSON Schema)</label>
            <textarea class="form-control form-control-sm font-monospace"
                      rows="4"
                      placeholder='{"type": "object", "properties": {...}, "required": [...]}'
                      data-playground-functions-target="functionParameters"
                      data-action="input->playground-functions#onFunctionChange"></textarea>
          </div>

          <div class="form-check form-check-inline">
            <input type="checkbox"
                   class="form-check-input"
                   id="strict_${index}"
                   data-playground-functions-target="functionStrict"
                   data-action="change->playground-functions#onFunctionChange">
            <label class="form-check-label small" for="strict_${index}">
              Strict mode (enforce schema)
            </label>
          </div>
        </div>
      </div>
    `
  }

  /**
   * Remove a function definition
   * @param {Event} event - Click event from remove button
   */
  removeFunction(event) {
    event.target.closest(".function-item").remove()

    // Show "no functions" message if list is empty
    if (this.functionItemTargets.length === 0) {
      this.functionsListTarget.innerHTML = `
        <div class="text-muted text-center py-3" data-playground-functions-target="noFunctionsMessage">
          <i class="bi bi-info-circle"></i>
          No functions defined. Click "Add Function" to create one.
        </div>
      `
    }

    this.dispatchConfigChange()
  }

  /**
   * Handle function field changes
   */
  onFunctionChange() {
    this.dispatchConfigChange()
  }

  /**
   * Get array of function configurations
   * @returns {Array<Object>} Array of function configurations
   */
  getFunctionsConfig() {
    const functions = []
    
    this.functionItemTargets.forEach(item => {
      const nameInput = item.querySelector('[data-playground-functions-target="functionName"]')
      const descInput = item.querySelector('[data-playground-functions-target="functionDescription"]')
      const outputDescInput = item.querySelector('[data-playground-functions-target="functionOutputDescription"]')
      const paramsInput = item.querySelector('[data-playground-functions-target="functionParameters"]')
      const strictInput = item.querySelector('[data-playground-functions-target="functionStrict"]')

      const name = nameInput?.value?.trim()
      if (!name) return

      let parameters = {}
      try {
        const paramsText = paramsInput?.value?.trim()
        if (paramsText) {
          parameters = JSON.parse(paramsText)
        }
      } catch (e) {
        console.warn("Invalid JSON in function parameters:", e)
      }

      const func = {
        name: name,
        description: descInput?.value?.trim() || "",
        parameters: parameters,
        strict: strictInput?.checked || false
      }

      // Add output_description if present
      const outputDesc = outputDescInput?.value?.trim()
      if (outputDesc) {
        func.output_description = outputDesc
      }

      functions.push(func)
    })

    return functions
  }

  /**
   * Dispatch custom event when config changes
   * @private
   */
  dispatchConfigChange() {
    const functions = this.getFunctionsConfig()
    
    this.dispatch("configChanged", {
      detail: { functions },
      prefix: "playground-functions"
    })
  }
}

