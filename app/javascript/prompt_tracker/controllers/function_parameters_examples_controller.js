import { Controller } from "@hotwired/stimulus"

/**
 * Function Parameters Examples Controller
 * 
 * Handles clicking on parameter examples in the modal and filling the
 * corresponding function parameter textarea with the selected example.
 * 
 * This controller is attached to the modal and listens for clicks on
 * example buttons. When clicked, it:
 * 1. Gets the parameter JSON from the button's data attribute
 * 2. Finds the currently focused/active function parameter textarea
 * 3. Fills it with the formatted JSON
 * 4. Closes the modal
 * 
 * @example
 * <div data-controller="function-parameters-examples">
 *   <button data-action="click->function-parameters-examples#useExample"
 *           data-parameters='{"type":"object",...}'>
 *     Use This Example
 *   </button>
 * </div>
 */
export default class extends Controller {
  connect() {
    console.log('[FunctionParametersExamplesController] Connected')
    
    // Store reference to the currently active function item when modal opens
    this.element.addEventListener('show.bs.modal', (event) => {
      // Find which function item triggered the modal
      const button = event.relatedTarget
      if (button) {
        const functionIndex = button.dataset.functionIndex
        console.log('[FunctionParametersExamplesController] Modal opened for function index:', functionIndex)
        this.currentFunctionIndex = functionIndex
      }
    })
  }

  /**
   * Handle clicking on an example button
   * Fills the parameter textarea with the example JSON
   */
  useExample(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const parametersJson = button.dataset.parameters
    
    if (!parametersJson) {
      console.error('[FunctionParametersExamplesController] No parameters data found on button')
      return
    }

    console.log('[FunctionParametersExamplesController] Using example:', parametersJson)

    // Parse and re-stringify to format nicely
    let formattedJson
    try {
      const parsed = JSON.parse(parametersJson)
      formattedJson = JSON.stringify(parsed, null, 2)
    } catch (e) {
      console.error('[FunctionParametersExamplesController] Failed to parse JSON:', e)
      formattedJson = parametersJson
    }

    // Find the parameter textarea for the current function
    const textarea = this.findParameterTextarea()
    
    if (textarea) {
      textarea.value = formattedJson
      
      // Trigger input event so playground-functions controller knows about the change
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
      
      console.log('[FunctionParametersExamplesController] Filled parameter textarea')
      
      // Close the modal
      this.closeModal()
    } else {
      console.error('[FunctionParametersExamplesController] Could not find parameter textarea')
    }
  }

  /**
   * Find the parameter textarea for the current function
   * @returns {HTMLTextAreaElement|null} The textarea element or null
   */
  findParameterTextarea() {
    // If we have a specific function index, find that textarea
    if (this.currentFunctionIndex !== undefined) {
      const textarea = document.querySelector(
        `textarea[data-playground-functions-target="functionParameters"][data-function-index="${this.currentFunctionIndex}"]`
      )
      if (textarea) {
        return textarea
      }
    }

    // Fallback: find the first visible parameter textarea
    const textareas = document.querySelectorAll('textarea[data-playground-functions-target="functionParameters"]')
    for (const textarea of textareas) {
      if (textarea.offsetParent !== null) { // Check if visible
        return textarea
      }
    }

    return null
  }

  /**
   * Close the modal
   */
  closeModal() {
    const modal = bootstrap.Modal.getInstance(this.element)
    if (modal) {
      modal.hide()
    }
  }
}

