import { Controller } from "@hotwired/stimulus"

/**
 * Playground Response Schema Stimulus Controller
 *
 * @description
 * Manages JSON response schema for structured outputs (OpenAI structured outputs, function calling, etc.).
 * Provides schema validation and editing functionality with tab indentation support.
 *
 * @responsibilities
 * - Manage JSON schema editor with tab indentation (2 spaces)
 * - Validate JSON schema syntax and structure
 * - Show validation errors and success messages
 * - Provide clear schema functionality
 * - Auto-hide success messages after 3 seconds
 *
 * @targets
 * - responseSchema: JSON schema textarea editor
 * - responseSchemaError: Error/success message display
 *
 * @values
 * None - operates on DOM targets only
 *
 * @outlets
 * None - independent schema management
 *
 * @events_dispatched
 * None - schema is collected by save controller via public method
 *
 * @events_listened_to
 * - click (validateResponseSchema): Validate schema button
 * - click (clearResponseSchema): Clear schema button
 * - keydown (responseSchema): Tab key for indentation
 *
 * @communication_pattern
 * Independent controller that provides a public method `getResponseSchema()` which is called
 * by the save controller to collect schema data when saving. Does not dispatch events or
 * communicate with other controllers.
 *
 * @public_methods
 * - getResponseSchema(): Returns parsed JSON schema object or null if empty/invalid
 *
 * @example
 * // In view:
 * <div data-controller="playground-response-schema">
 *   <textarea data-playground-response-schema-target="responseSchema"></textarea>
 *   <button data-action="click->playground-response-schema#validateResponseSchema">Validate</button>
 *   <button data-action="click->playground-response-schema#clearResponseSchema">Clear</button>
 *   <div data-playground-response-schema-target="responseSchemaError" class="d-none"></div>
 * </div>
 */
export default class extends Controller {
  static targets = [
    "responseSchema",
    "responseSchemaError"
  ]

  connect() {
    console.log('[PlaygroundResponseSchemaController] ========== CONNECT ==========')
    console.log('[PlaygroundResponseSchemaController] Element:', this.element)
    console.log('[PlaygroundResponseSchemaController] Has responseSchema target?', this.hasResponseSchemaTarget)
    console.log('[PlaygroundResponseSchemaController] ========== CONNECT COMPLETE ==========')

    // Attach tab key handler for indentation
    if (this.hasResponseSchemaTarget) {
      this.responseSchemaTarget.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault()
          const start = this.responseSchemaTarget.selectionStart
          const end = this.responseSchemaTarget.selectionEnd
          const value = this.responseSchemaTarget.value
          this.responseSchemaTarget.value = value.substring(0, start) + '  ' + value.substring(end)
          this.responseSchemaTarget.selectionStart = this.responseSchemaTarget.selectionEnd = start + 2
        }
      })
    }
  }

  // Action: Validate response schema (called from view button)
  validateResponseSchema(event) {
    console.log('[PlaygroundResponseSchemaController] ========== VALIDATE SCHEMA ==========')
    event.preventDefault()

    const schemaText = this.getSchemaText()
    console.log('[PlaygroundResponseSchemaController] Schema to validate:', schemaText)

    if (!schemaText) {
      console.log('[PlaygroundResponseSchemaController] No schema to validate')
      this.showError('No schema to validate')
      return
    }

    try {
      const parsed = JSON.parse(schemaText)
      console.log('[PlaygroundResponseSchemaController] Schema is valid JSON:', parsed)

      // Basic validation
      if (typeof parsed !== 'object' || Array.isArray(parsed)) {
        this.showError('Schema must be a JSON object')
        return
      }

      // Check for required fields (OpenAI structured outputs format)
      if (!parsed.type) {
        this.showError('Schema must have a "type" field')
        return
      }

      this.showSuccess('Schema is valid!')
      console.log('[PlaygroundResponseSchemaController] Schema validation passed')
    } catch (error) {
      console.error('[PlaygroundResponseSchemaController] Schema validation error:', error)
      this.showError(`Invalid JSON: ${error.message}`)
    }

    console.log('[PlaygroundResponseSchemaController] ========== VALIDATE COMPLETE ==========')
  }

  // Action: Clear response schema (called from view button)
  clearResponseSchema(event) {
    console.log('[PlaygroundResponseSchemaController] clearResponseSchema() called')
    event.preventDefault()

    if (this.hasResponseSchemaTarget) {
      this.responseSchemaTarget.value = ''
      this.hideError()
      console.log('[PlaygroundResponseSchemaController] Schema cleared')
    }
  }

  // Get raw schema text from textarea
  getSchemaText() {
    if (!this.hasResponseSchemaTarget) {
      return null
    }
    return this.responseSchemaTarget.value.trim()
  }

  // Get response schema as parsed object (called by save controller)
  getResponseSchema() {
    const schemaText = this.getSchemaText()
    console.log('[PlaygroundResponseSchemaController] Getting schema, length:', schemaText?.length || 0)

    if (!schemaText) {
      return null
    }

    try {
      const parsed = JSON.parse(schemaText)
      console.log('[PlaygroundResponseSchemaController] Parsed schema:', parsed)
      return parsed
    } catch (error) {
      console.error('[PlaygroundResponseSchemaController] Failed to parse schema:', error.message)
      return null
    }
  }

  // Show error message
  showError(message) {
    console.log('[PlaygroundResponseSchemaController] Showing error:', message)

    if (this.hasResponseSchemaErrorTarget) {
      this.responseSchemaErrorTarget.innerHTML = `<strong>Error:</strong> ${message}`
      this.responseSchemaErrorTarget.classList.remove('d-none', 'alert-success')
      this.responseSchemaErrorTarget.classList.add('alert-danger')
    }
  }

  // Show success message
  showSuccess(message) {
    console.log('[PlaygroundResponseSchemaController] Showing success:', message)

    if (this.hasResponseSchemaErrorTarget) {
      this.responseSchemaErrorTarget.innerHTML = `<strong>Success:</strong> ${message}`
      this.responseSchemaErrorTarget.classList.remove('d-none', 'alert-danger')
      this.responseSchemaErrorTarget.classList.add('alert-success')

      // Auto-hide after 3 seconds
      setTimeout(() => {
        this.hideError()
      }, 3000)
    }
  }

  // Hide error/success message
  hideError() {
    console.log('[PlaygroundResponseSchemaController] Hiding error')

    if (this.hasResponseSchemaErrorTarget) {
      this.responseSchemaErrorTarget.classList.add('d-none')
      this.responseSchemaErrorTarget.innerHTML = ''
    }
  }
}
