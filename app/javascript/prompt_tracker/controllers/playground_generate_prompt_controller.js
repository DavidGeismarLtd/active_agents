import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Playground Generate Prompt Controller
 *
 * @description
 * Handles AI-powered prompt generation and enhancement from natural language descriptions.
 * Manages the AI button state (Generate vs Enhance based on content) and modal interactions.
 *
 * @responsibilities
 * - AI button state management (Generate vs Enhance based on content)
 * - Listen for prompt changes to update button state
 * - Modal management for generation input
 * - API calls for prompt generation
 * - Insert generated prompts into editors
 * - Show generating/loading state
 *
 * @targets
 * - aiButton: The generate/enhance button
 * - aiButtonText: Text inside AI button
 * - aiButtonIcon: Icon inside AI button
 *
 * @values
 * - generateUrl: String - API endpoint for generation
 *
 * @events_listened
 * - playground-prompt-editor:promptChanged: Update AI button state
 */
export default class extends Controller {
  static targets = [
    "aiButton",
    "aiButtonText",
    "aiButtonIcon"
  ]

  static values = {
    generateUrl: String
  }

  connect() {
    console.log("[PlaygroundGeneratePromptController] Connected")
    console.log("[PlaygroundGeneratePromptController] generateUrl:", this.generateUrlValue)
    this.generatingModal = null
    this.attachModalEventListeners()
    // Initial button state will be set when we receive the first promptChanged event
  }

  /**
   * Attach event listeners for modal buttons that get moved outside controller scope
   */
  attachModalEventListeners() {
    const generateButton = document.getElementById("generatePromptButton")
    console.log("[PlaygroundGeneratePromptController] Looking for #generatePromptButton:", !!generateButton)
    if (generateButton) {
      generateButton.addEventListener("click", () => {
        console.log("[PlaygroundGeneratePromptController] Generate button clicked")
        this.submitGeneration()
      })
    }
  }

  /**
   * Action: Called when prompt content changes (via event listener)
   * Updates the AI button state based on whether prompts have content
   */
  onPromptChanged(event) {
    console.log("[PlaygroundGeneratePromptController] onPromptChanged", event.detail)
    const { systemPrompt, userPrompt } = event.detail
    this.updateButtonState(systemPrompt, userPrompt)
  }

  /**
   * Update AI button state based on content
   */
  updateButtonState(systemPrompt = "", userPrompt = "") {
    if (!this.hasAiButtonTarget) {
      console.log("[PlaygroundGeneratePromptController] No AI button target")
      return
    }

    const hasContent = systemPrompt.trim().length > 0 || userPrompt.trim().length > 0
    console.log("[PlaygroundGeneratePromptController] Has content?", hasContent)

    if (hasContent) {
      // Show "Enhance" mode
      if (this.hasAiButtonTextTarget) {
        this.aiButtonTextTarget.textContent = "Enhance with AI"
      }
      if (this.hasAiButtonIconTarget) {
        this.aiButtonIconTarget.className = "bi bi-stars"
      }
    } else {
      // Show "Generate" mode
      if (this.hasAiButtonTextTarget) {
        this.aiButtonTextTarget.textContent = "Generate with AI"
      }
      if (this.hasAiButtonIconTarget) {
        this.aiButtonIconTarget.className = "bi bi-magic"
      }
    }
  }

  /**
   * Action: Open the generate prompt modal
   */
  openModal() {
    console.log("[PlaygroundGeneratePromptController] openModal()")
    const modalEl = document.getElementById("generatePromptModal")
    if (modalEl) {
      const modal = new Modal(modalEl)
      modal.show()
    }
  }

  /**
   * Submit generation request
   */
  async submitGeneration() {
    console.log("[PlaygroundGeneratePromptController] submitGeneration()")
    const descriptionTextarea = document.getElementById("generateDescription")

    if (!descriptionTextarea) {
      console.error("[PlaygroundGeneratePromptController] Description textarea not found!")
      return
    }

    const description = descriptionTextarea.value.trim()

    if (!description) {
      this.showAlert("Please describe what your prompt should do", "warning")
      return
    }

    // Close the input modal
    const inputModalEl = document.getElementById("generatePromptModal")
    if (inputModalEl) {
      const inputModal = Modal.getInstance(inputModalEl)
      if (inputModal) inputModal.hide()
    }

    // Show generating modal
    this.showGeneratingModal()

    try {
      await this.generatePromptFromDescription(description)
    } finally {
      this.hideGeneratingModal()
      if (descriptionTextarea) {
        descriptionTextarea.value = ""
      }
    }
  }

  /**
   * Generate prompt from description with animation
   */
  async generatePromptFromDescription(description) {
    try {
      const response = await fetch(this.generateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({ description })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || `Server error (${response.status})`)
      }

      const data = await response.json()

      if (data.success) {
        // Insert generated prompts directly into DOM
        this.insertGeneratedPrompts(data)
        const message = data.explanation || "Prompt generated successfully!"
        this.showAlert(message, "success")
      } else {
        throw new Error(data.error || "Generation failed")
      }
    } catch (error) {
      console.error("Generation error:", error)
      this.showAlert(`Generation failed: ${error.message}`, "danger")
    }
  }

  /**
   * Insert generated prompts into the editors
   * Directly accesses DOM elements by ID since they're well-known
   */
  insertGeneratedPrompts(data) {
    console.log("[PlaygroundGeneratePromptController] insertGeneratedPrompts", data)

    // Insert system prompt
    if (data.system_prompt) {
      const systemEditor = document.getElementById("system-prompt-editor")
      if (systemEditor) {
        systemEditor.value = data.system_prompt
        systemEditor.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }

    // Insert user prompt
    if (data.user_prompt) {
      const userEditor = document.getElementById("user-prompt-editor")
      if (userEditor) {
        userEditor.value = data.user_prompt
        userEditor.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }

    console.log("[PlaygroundGeneratePromptController] Prompts inserted")
  }

  showGeneratingModal() {
    const modalEl = document.getElementById("generatingModal")
    if (modalEl) {
      this.generatingModal = new Modal(modalEl)
      this.generatingModal.show()
    }
  }

  hideGeneratingModal() {
    if (this.generatingModal) {
      this.generatingModal.hide()
      this.generatingModal = null
    }
  }

  showAlert(message, type) {
    // Create alert element
    const alertDiv = document.createElement("div")
    alertDiv.className = `alert alert-${type} alert-dismissible fade show position-fixed`
    alertDiv.style.cssText = "top: 20px; right: 20px; z-index: 9999; max-width: 400px;"
    alertDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    document.body.appendChild(alertDiv)

    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      alertDiv.remove()
    }, 5000)
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
