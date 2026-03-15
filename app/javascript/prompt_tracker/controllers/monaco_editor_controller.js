import { Controller } from "@hotwired/stimulus"

/**
 * Monaco Editor Controller
 *
 * @description
 * Integrates Monaco Editor (VS Code's editor) for code editing with syntax highlighting,
 * autocomplete, and error detection.
 *
 * @responsibilities
 * - Initialize Monaco Editor instances
 * - Sync editor content with hidden textarea
 * - Configure language-specific features (Ruby, JSON)
 * - Handle editor resize and theme changes
 *
 * @targets
 * - container: The div where Monaco will be mounted
 * - textarea: The hidden textarea to sync with
 *
 * @values
 * - language: Programming language (ruby, json, etc.)
 * - theme: Editor theme (vs, vs-dark)
 * - readOnly: Whether editor is read-only
 * - minimap: Whether to show minimap
 * - lineNumbers: Whether to show line numbers
 */
export default class extends Controller {
  static targets = ["container", "textarea"]
  static values = {
    language: { type: String, default: "ruby" },
    theme: { type: String, default: "vs" },
    readOnly: { type: Boolean, default: false },
    minimap: { type: Boolean, default: true },
    lineNumbers: { type: Boolean, default: true },
    height: { type: String, default: "400px" }
  }

  connect() {
    console.log("[MonacoEditorController] Connected", {
      language: this.languageValue,
      theme: this.themeValue
    })

    // Wait for Monaco to be loaded
    this.loadMonaco().then(() => {
      this.initializeEditor()
    })
  }

  disconnect() {
    if (this.editor) {
      this.editor.dispose()
      this.editor = null
    }
  }

  /**
   * Load Monaco Editor from CDN
   */
  async loadMonaco() {
    // Check if Monaco is already loaded
    if (window.monaco) {
      return Promise.resolve()
    }

    return new Promise((resolve, reject) => {
      // Set Monaco loader configuration
      window.require = { paths: { vs: "https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs" } }

      // Load Monaco loader
      const loaderScript = document.createElement("script")
      loaderScript.src = "https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs/loader.js"
      loaderScript.onload = () => {
        // Load Monaco Editor
        window.require(["vs/editor/editor.main"], () => {
          console.log("[MonacoEditorController] Monaco loaded")
          resolve()
        })
      }
      loaderScript.onerror = reject
      document.head.appendChild(loaderScript)
    })
  }

  /**
   * Initialize Monaco Editor
   */
  initializeEditor() {
    if (!this.hasContainerTarget || !this.hasTextareaTarget) {
      console.error("[MonacoEditorController] Missing container or textarea target")
      return
    }

    // Set container height
    this.containerTarget.style.height = this.heightValue
    this.containerTarget.style.border = "1px solid #dee2e6"
    this.containerTarget.style.borderRadius = "0.375rem"

    // Get initial value from textarea
    const initialValue = this.textareaTarget.value || ""

    // Create editor
    this.editor = window.monaco.editor.create(this.containerTarget, {
      value: initialValue,
      language: this.languageValue,
      theme: this.themeValue,
      readOnly: this.readOnlyValue,
      minimap: { enabled: this.minimapValue },
      lineNumbers: this.lineNumbersValue ? "on" : "off",
      fontSize: 14,
      fontFamily: "'JetBrains Mono', 'Monaco', 'Menlo', 'Consolas', monospace",
      automaticLayout: true,
      scrollBeyondLastLine: false,
      wordWrap: "on",
      tabSize: 2,
      insertSpaces: true,
      formatOnPaste: true,
      formatOnType: true
    })

    // Sync editor content to textarea on change
    this.editor.onDidChangeModelContent(() => {
      this.textareaTarget.value = this.editor.getValue()
      // Trigger input event for form validation
      this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }))
    })

    // Hide the original textarea
    this.textareaTarget.style.display = "none"

    console.log("[MonacoEditorController] Editor initialized")
  }

  /**
   * Update editor theme (called when page theme changes)
   */
  updateTheme(theme) {
    if (this.editor) {
      window.monaco.editor.setTheme(theme === "dark" ? "vs-dark" : "vs")
    }
  }

  /**
   * Get editor value
   */
  getValue() {
    return this.editor ? this.editor.getValue() : ""
  }

  /**
   * Set editor value
   */
  setValue(value) {
    if (this.editor) {
      this.editor.setValue(value)
    }
  }

  /**
   * Set editor language
   * @param {String} language - Monaco language identifier (e.g., "ruby", "python", "javascript")
   */
  setLanguage(language) {
    if (this.editor) {
      const model = this.editor.getModel()
      if (model) {
        window.monaco.editor.setModelLanguage(model, language)
        console.log("[MonacoEditorController] Language changed to:", language)
      }
    }
  }
}
