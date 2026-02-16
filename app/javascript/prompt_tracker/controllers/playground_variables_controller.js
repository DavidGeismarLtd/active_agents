import { Controller } from "@hotwired/stimulus"

/**
 * Playground Variables Controller
 *
 * @description
 * Handles variable extraction from prompts and manages variable input fields.
 * Extracts variables from {{ variable }} and {% tag variable %} syntax.
 *
 * @responsibilities
 * - Extract variables from prompt templates
 * - Dynamically generate input fields for detected variables
 * - Preserve existing values when rebuilding inputs
 * - Dispatch events when variable values change
 *
 * @targets
 * - container: The container for variable inputs
 *
 * @events_listened
 * - playground-prompt-editor:promptChanged: Re-extract variables from prompts
 *
 * @events_dispatched
 * - playground-variables:changed: When variable values change
 */
export default class extends Controller {
  static targets = ["container"]

  connect() {
    console.log("[PlaygroundVariablesController] Connected")
    console.log("[PlaygroundVariablesController] Has container target?", this.hasContainerTarget)
    this.currentVariables = {}

    // Listen for prompt changes from the prompt editor controller
    // The event bubbles up from the prompt editor, so we listen on the document
    this.boundOnPromptChanged = this.onPromptChanged.bind(this)
    document.addEventListener("playground-prompt-editor:promptChanged", this.boundOnPromptChanged)
  }

  disconnect() {
    document.removeEventListener("playground-prompt-editor:promptChanged", this.boundOnPromptChanged)
  }

  /**
   * Called when prompt content changes (via event listener)
   */
  onPromptChanged(event) {
    console.log("[PlaygroundVariablesController] onPromptChanged", event.detail)
    const { systemPrompt, userPrompt } = event.detail
    this.updateVariablesFromPrompts(systemPrompt, userPrompt)
  }

  /**
   * Action: Called when a variable input changes
   */
  onVariableInput(event) {
    const input = event.target
    const varName = input.dataset.variable
    if (varName) {
      this.currentVariables[varName] = input.value
      console.log("[PlaygroundVariablesController] Variable changed:", varName, "=", input.value)
      this.dispatchChangedEvent()
    }
  }

  /**
   * Extract variables from both prompts and update inputs
   */
  updateVariablesFromPrompts(systemPrompt = "", userPrompt = "") {
    const variables = this.extractVariables(systemPrompt + " " + userPrompt)
    console.log("[PlaygroundVariablesController] Extracted variables:", variables)
    this.rebuildVariableInputs(variables)
  }

  /**
   * Extract variable names from template text
   */
  extractVariables(template) {
    const variables = new Set()

    // Mustache-style: {{variable}} or {{ variable }}
    const mustacheMatches = template.matchAll(/\{\{\s*(\w+)\s*\}\}/g)
    for (const match of mustacheMatches) {
      variables.add(match[1])
    }

    // Liquid filters: {{ variable | filter }}
    const filterMatches = template.matchAll(/\{\{\s*(\w+)\s*\|/g)
    for (const match of filterMatches) {
      variables.add(match[1])
    }

    // Liquid object notation: {{ object.property }}
    const objectMatches = template.matchAll(/\{\{\s*(\w+)\./g)
    for (const match of objectMatches) {
      variables.add(match[1])
    }

    // Liquid conditionals: {% if variable %}
    const conditionalMatches = template.matchAll(/\{%\s*if\s+(\w+)/g)
    for (const match of conditionalMatches) {
      variables.add(match[1])
    }

    // Liquid loops: {% for item in items %}
    const loopMatches = template.matchAll(/\{%\s*for\s+\w+\s+in\s+(\w+)/g)
    for (const match of loopMatches) {
      variables.add(match[1])
    }

    return Array.from(variables).sort()
  }

  /**
   * Rebuild variable input fields
   */
  rebuildVariableInputs(variables) {
    if (!this.hasContainerTarget) {
      console.log("[PlaygroundVariablesController] No container target")
      return
    }

    // Preserve current values
    const preservedValues = { ...this.currentVariables }

    if (variables.length === 0) {
      this.containerTarget.innerHTML = '<p class="text-muted">No variables detected. Use {{ variable_name }} syntax.</p>'
      this.currentVariables = {}
      return
    }

    // Build new inputs
    let html = ""
    console.log("[PlaygroundVariablesController] Rebuilding variable inputs for:", variables)
    for (const varName of variables) {
      const value = preservedValues[varName] || ""
      html += `
        <div class="mb-3">
          <label for="var-${varName}" class="form-label"><code>${varName}</code></label>
          <input
            type="text"
            class="form-control variable-input"
            id="var-${varName}"
            data-variable="${varName}"
            value="${this.escapeHtml(value)}"
            placeholder="Enter value for ${varName}"
            data-action="input->playground-variables#onVariableInput"
          >
        </div>
      `
      this.currentVariables[varName] = value
    }

    this.containerTarget.innerHTML = html
  }

  /**
   * Escape HTML special characters
   */
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Public: Get all variable values
   */
  getVariables() {
    return { ...this.currentVariables }
  }

  /**
   * Public: Check if any variables are unfilled
   */
  hasUnfilledVariables() {
    return Object.values(this.currentVariables).some(v => !v || v.trim() === "")
  }

  /**
   * Public: Get list of unfilled variable names
   */
  getUnfilledVariables() {
    return Object.entries(this.currentVariables)
      .filter(([_, value]) => !value || value.trim() === "")
      .map(([name, _]) => name)
  }

  /**
   * Dispatch changed event
   */
  dispatchChangedEvent() {
    this.dispatch("changed", {
      detail: { variables: this.getVariables() },
      bubbles: true
    })
  }
}
