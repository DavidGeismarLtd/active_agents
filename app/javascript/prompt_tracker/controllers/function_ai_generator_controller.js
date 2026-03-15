import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

/**
 * Function AI Generator Controller
 *
 * @description
 * Handles the "Create with AI" feature for generating function code from descriptions.
 * Shows a modal for input, calls the AI generation endpoint, and populates the form.
 *
 * @responsibilities
 * - Show/hide AI generation modal
 * - Submit description and language to backend
 * - Handle loading states
 * - Populate form fields with AI-generated content
 * - Handle errors gracefully
 *
 * @outlets
 * - monacoEditor: Monaco Editor controllers to populate with generated code
 */
export default class extends Controller {
  static outlets = ["monaco-editor"]

  connect() {
    console.log("[FunctionAiGeneratorController] Connected")
    console.log("[FunctionAiGeneratorController] Element:", this.element)
    console.log("[FunctionAiGeneratorController] Monaco outlets on connect:", this.monacoEditorOutlets.length)

    // Log all elements with monaco-editor controller
    const monacoElements = this.element.querySelectorAll('[data-controller*="monaco-editor"]')
    console.log("[FunctionAiGeneratorController] Found monaco-editor elements:", monacoElements.length)
    monacoElements.forEach((el, i) => {
      console.log(`  [${i}]:`, el.dataset.controller, "outlet attr:", el.dataset.functionAiGeneratorMonacoEditorOutlet)
    })

    this.attachModalEventListeners()
  }

  monacoEditorOutletConnected(outlet, element) {
    console.log("[FunctionAiGeneratorController] Monaco outlet CONNECTED!", {
      outlet,
      element,
      totalOutlets: this.monacoEditorOutlets.length
    })
  }

  monacoEditorOutletDisconnected(outlet, element) {
    console.log("[FunctionAiGeneratorController] Monaco outlet DISCONNECTED!", {
      outlet,
      element,
      totalOutlets: this.monacoEditorOutlets.length
    })
  }

  /**
   * Attach event listeners for modal buttons that get moved outside controller scope
   */
  attachModalEventListeners() {
    const generateButton = document.getElementById("aiGenerateButton")
    console.log("[FunctionAiGeneratorController] Looking for #aiGenerateButton:", !!generateButton)
    if (generateButton) {
      generateButton.addEventListener("click", () => {
        console.log("[FunctionAiGeneratorController] Generate button clicked")
        this.generate()
      })
    }
  }

  /**
   * Show the AI generation modal
   */
  showModal() {
    console.log("[FunctionAiGeneratorController] showModal called")

    const modalEl = document.getElementById("aiGeneratorModal")
    if (!modalEl) {
      console.error("[FunctionAiGeneratorController] Modal element not found!")
      return
    }

    const modal = new bootstrap.Modal(modalEl)
    modal.show()

    // Clear previous values
    const descriptionEl = document.getElementById("ai_description")
    const languageEl = document.getElementById("ai_language")

    if (descriptionEl) {
      descriptionEl.value = ""
    }
    if (languageEl) {
      languageEl.value = "ruby"
    }
    this.hideError()
  }

  /**
   * Generate function using AI
   */
  async generate() {
    const descriptionEl = document.getElementById("ai_description")
    const languageEl = document.getElementById("ai_language")

    if (!descriptionEl || !languageEl) {
      console.error("[FunctionAiGeneratorController] Form elements not found")
      return
    }

    const description = descriptionEl.value.trim()
    const language = languageEl.value

    if (!description) {
      this.showError("Please enter a description")
      return
    }

    this.setLoading(true)
    this.hideError()

    try {
      const response = await fetch("/prompt_tracker/functions/generate_with_ai", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          description: description,
          language: language
        })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || "Failed to generate function")
      }

      const result = await response.json()
      console.log("[FunctionAiGeneratorController] Received result:", result)

      // Populate form fields with generated content
      this.populateForm(result)

      // Close modal
      const modalEl = document.getElementById("aiGeneratorModal")
      if (modalEl) {
        const modal = bootstrap.Modal.getInstance(modalEl)
        if (modal) modal.hide()
      }

      // Show success message
      this.showSuccessToast("Function generated successfully! Review and edit as needed.")

    } catch (error) {
      console.error("[FunctionAiGeneratorController] Generation failed:", error)
      this.showError(error.message)
    } finally {
      this.setLoading(false)
    }
  }

  /**
   * Populate form fields with AI-generated content
   */
  populateForm(result) {
    console.log("[FunctionAiGeneratorController] Populating form with result:", result)

    // Populate text fields
    const nameField = document.getElementById("function_definition_name")
    const descField = document.getElementById("function_definition_description")
    const langField = document.getElementById("function_definition_language")
    const catField = document.getElementById("function_definition_category")

    console.log("[FunctionAiGeneratorController] Found fields:", {
      name: !!nameField,
      description: !!descField,
      language: !!langField,
      category: !!catField
    })

    if (nameField) nameField.value = result.name || ""
    if (descField) descField.value = result.description || ""
    if (langField) langField.value = result.language || "ruby"
    if (catField) catField.value = result.category || "utility"

    // Populate code using Monaco Editor
    console.log("[FunctionAiGeneratorController] Monaco outlets count:", this.monacoEditorOutlets.length)

    // Find Monaco editors by data-field attribute
    const codeEditorEl = this.element.querySelector('[data-field="code"][data-controller*="monaco-editor"]')
    const paramsEditorEl = this.element.querySelector('[data-field="parameters"][data-controller*="monaco-editor"]')

    console.log("[FunctionAiGeneratorController] Code editor element found:", !!codeEditorEl)
    console.log("[FunctionAiGeneratorController] Params editor element found:", !!paramsEditorEl)

    // Get Stimulus controller instances
    const codeEditor = codeEditorEl ? this.application.getControllerForElementAndIdentifier(codeEditorEl, "monaco-editor") : null
    const paramsEditor = paramsEditorEl ? this.application.getControllerForElementAndIdentifier(paramsEditorEl, "monaco-editor") : null

    console.log("[FunctionAiGeneratorController] Code editor controller:", !!codeEditor)
    console.log("[FunctionAiGeneratorController] Params editor controller:", !!paramsEditor)

    if (codeEditor) {
      codeEditor.setValue(result.code || "")
    }

    if (paramsEditor) {
      paramsEditor.setValue(JSON.stringify(result.parameters, null, 2))
    }

    // Populate dependencies
    const dependenciesTextarea = document.getElementById("function_definition_dependencies")
    if (dependenciesTextarea && result.dependencies) {
      dependenciesTextarea.value = result.dependencies.join("\n")
    }

    // Populate example input/output using Monaco Editors
    const exampleInputEl = this.element.querySelector('[data-field="example_input"][data-controller*="monaco-editor"]')
    const exampleOutputEl = this.element.querySelector('[data-field="example_output"][data-controller*="monaco-editor"]')

    const exampleInputEditor = exampleInputEl ? this.application.getControllerForElementAndIdentifier(exampleInputEl, "monaco-editor") : null
    const exampleOutputEditor = exampleOutputEl ? this.application.getControllerForElementAndIdentifier(exampleOutputEl, "monaco-editor") : null

    console.log("[FunctionAiGeneratorController] Example input editor:", !!exampleInputEditor)
    console.log("[FunctionAiGeneratorController] Example output editor:", !!exampleOutputEditor)

    if (exampleInputEditor && result.example_input) {
      exampleInputEditor.setValue(JSON.stringify(result.example_input, null, 2))
    }

    if (exampleOutputEditor && result.example_output) {
      exampleOutputEditor.setValue(JSON.stringify(result.example_output, null, 2))
    }
  }

  /**
   * Set loading state
   */
  setLoading(isLoading) {
    const submitButton = document.getElementById("aiGenerateButton")
    const loadingSpinner = document.getElementById("aiGenerateSpinner")

    if (submitButton) {
      submitButton.disabled = isLoading
    }
    if (loadingSpinner) {
      loadingSpinner.classList.toggle("d-none", !isLoading)
    }
  }

  /**
   * Show error message
   */
  showError(message) {
    const errorMessage = document.getElementById("aiGenerateError")
    if (errorMessage) {
      errorMessage.textContent = message
      errorMessage.classList.remove("d-none")
    }
  }

  /**
   * Hide error message
   */
  hideError() {
    const errorMessage = document.getElementById("aiGenerateError")
    if (errorMessage) {
      errorMessage.classList.add("d-none")
    }
  }

  /**
   * Show success toast notification
   */
  showSuccessToast(message) {
    // Create toast element
    const toast = document.createElement("div")
    toast.className = "toast align-items-center text-white bg-success border-0"
    toast.setAttribute("role", "alert")
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">${message}</div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
      </div>
    `

    // Add to page
    document.body.appendChild(toast)

    // Show toast
    const bsToast = new bootstrap.Toast(toast)
    bsToast.show()

    // Remove after hidden
    toast.addEventListener("hidden.bs.toast", () => toast.remove())
  }

  /**
   * Get CSRF token
   */
  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
