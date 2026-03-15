import { Controller } from "@hotwired/stimulus"

/**
 * Function Language Switcher Controller
 *
 * Updates Monaco editor language when the runtime/language dropdown changes.
 * Maps AWS Lambda runtime identifiers to Monaco editor language identifiers.
 */
export default class extends Controller {
  connect() {
    console.log("[FunctionLanguageSwitcher] Connected")
  }

  /**
   * Update Monaco editor language when runtime selection changes
   */
  updateEditorLanguage(event) {
    const runtime = event.target.value
    console.log("[FunctionLanguageSwitcher] Runtime changed to:", runtime)

    // Map runtime to Monaco language
    const monacoLanguage = this.runtimeToMonacoLanguage(runtime)
    console.log("[FunctionLanguageSwitcher] Monaco language:", monacoLanguage)

    // Find the code Monaco editor
    const codeEditorEl = this.element.querySelector('[data-field="code"][data-controller*="monaco-editor"]')
    
    if (!codeEditorEl) {
      console.warn("[FunctionLanguageSwitcher] Code editor element not found")
      return
    }

    // Get the Monaco editor controller
    const codeEditor = this.application.getControllerForElementAndIdentifier(codeEditorEl, "monaco-editor")
    
    if (!codeEditor) {
      console.warn("[FunctionLanguageSwitcher] Code editor controller not found")
      return
    }

    // Update the language
    if (codeEditor.setLanguage) {
      codeEditor.setLanguage(monacoLanguage)
      console.log("[FunctionLanguageSwitcher] Language updated successfully")
    } else {
      console.warn("[FunctionLanguageSwitcher] setLanguage method not available on Monaco editor")
    }
  }

  /**
   * Map AWS Lambda runtime to Monaco editor language
   * @param {String} runtime - AWS Lambda runtime (e.g., "ruby3.3", "python3.12", "nodejs22.x")
   * @returns {String} Monaco language identifier (e.g., "ruby", "python", "javascript")
   */
  runtimeToMonacoLanguage(runtime) {
    if (runtime.startsWith("ruby")) {
      return "ruby"
    } else if (runtime.startsWith("python")) {
      return "python"
    } else if (runtime.startsWith("nodejs")) {
      return "javascript"
    } else {
      return "plaintext"
    }
  }
}

