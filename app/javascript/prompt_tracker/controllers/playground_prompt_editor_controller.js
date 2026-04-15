import { Controller } from "@hotwired/stimulus"

/**
 * Playground Prompt Editor Controller
 *
 * @description
 * Manages prompt text editing functionality including system prompt
 * textarea, character counting, and tab key indentation.
 *
 * @responsibilities
 * - Manage system prompt textarea editor
 * - Handle tab key for 2-space indentation
 * - Update character count with color coding
 * - Dispatch promptChanged events when content changes
 *
 * @targets
 * - systemPromptEditor: System prompt textarea
 * - charCount: Character count display element
 *
 * @events_dispatched
 * - playground-prompt-editor:promptChanged: When prompt changes
 *   Detail: { systemPrompt, userPrompt }
 */
export default class extends Controller {
  static targets = [
    "systemPromptEditor",
    "charCount"
  ]

  connect() {
    console.log("[PlaygroundPromptEditorController] Connected")
    this.attachTabKeyListeners()
    this.updateCharCount()
  }

  /**
   * Attach tab key listeners for 2-space indentation
   */
  attachTabKeyListeners() {
    if (this.hasSystemPromptEditorTarget) {
      this.systemPromptEditorTarget.addEventListener("keydown", (e) => {
        if (e.key === "Tab") {
          e.preventDefault()
          this.insertTabSpaces(this.systemPromptEditorTarget)
        }
      })
    }
  }

  /**
   * Insert 2 spaces at cursor position (tab replacement)
   */
  insertTabSpaces(textarea) {
    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const value = textarea.value
    textarea.value = value.substring(0, start) + "  " + value.substring(end)
    textarea.selectionStart = textarea.selectionEnd = start + 2
    textarea.dispatchEvent(new Event("input"))
  }

  /**
   * Action: System prompt input
   */
  onSystemPromptInput() {
    console.log("[PlaygroundPromptEditorController] onSystemPromptInput")
    this.updateCharCount()
    this.dispatchPromptChanged()
  }

  /**
   * Update character count with color coding
   */
  updateCharCount() {
    if (!this.hasCharCountTarget) return

    const totalLength = this.hasSystemPromptEditorTarget
      ? this.systemPromptEditorTarget.value.length
      : 0

    this.charCountTarget.textContent = `${totalLength.toLocaleString()} chars`

    // Color coding based on length
    this.charCountTarget.classList.remove("bg-success", "bg-warning", "bg-danger", "bg-info")
    if (totalLength === 0) {
      this.charCountTarget.classList.add("bg-info")
    } else if (totalLength < 1000) {
      this.charCountTarget.classList.add("bg-success")
    } else if (totalLength < 5000) {
      this.charCountTarget.classList.add("bg-warning")
    } else {
      this.charCountTarget.classList.add("bg-danger")
    }
  }

  /**
   * Dispatch promptChanged event
   */
  dispatchPromptChanged() {
    this.dispatch("promptChanged", {
      detail: {
        systemPrompt: this.getSystemPrompt(),
        userPrompt: this.getUserPrompt()
      },
      bubbles: true
    })
  }

  // ========== Public Getters ==========

  getSystemPrompt() {
    return this.hasSystemPromptEditorTarget
      ? this.systemPromptEditorTarget.value
      : ""
  }

  getUserPrompt() {
    return ""
  }
}
