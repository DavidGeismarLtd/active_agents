import { Controller } from "@hotwired/stimulus"

/**
 * Shared Conversation Controller
 * Used by: Prompt Playground (Response API mode), Assistant Playground
 *
 * Handles:
 * - Sending messages to the server
 * - Displaying responses
 * - Resetting conversations
 * - Typing indicators
 * - Visibility toggling based on provider
 *
 * Uses outlets to specialized controllers for collecting data:
 * - playground-prompt-editor: for system_prompt and user_prompt
 * - playground-model-config: for model configuration
 * - playground-variables: for template variables
 */
export default class extends Controller {
  static targets = [
    "messagesContainer",
    "messageInput",
    "sendButton",
    "typingIndicator",
    "panel",
    "messageCount"
  ]

  static values = {
    sendUrl: String,
    resetUrl: String,
    visible: { type: Boolean, default: false }
  }

  static outlets = [
    "playground-prompt-editor",
    "playground-model-config",
    "playground-variables"
  ]

  connect() {
    console.log("Conversation controller connected")
    this.setupKeyboardShortcuts()
    this.updateVisibility()
  }

  // Called when visible value changes
  visibleValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    if (this.hasPanelTarget) {
      this.panelTarget.style.display = this.visibleValue ? "" : "none"
    }
  }

  // Show the conversation panel
  show() {
    this.visibleValue = true
  }

  // Hide the conversation panel
  hide() {
    this.visibleValue = false
  }

  setupKeyboardShortcuts() {
    if (this.hasMessageInputTarget) {
      this.messageInputTarget.addEventListener("keydown", (e) => {
        // Ctrl/Cmd + Enter to send
        const isMac = navigator.userAgent.indexOf("Mac") !== -1
        const modKey = isMac ? e.metaKey : e.ctrlKey

        if (modKey && e.key === "Enter") {
          e.preventDefault()
          this.submit(e)
        }
      })
    }
  }

  async submit(event) {
    if (event) event.preventDefault()

    const content = this.messageInputTarget.value.trim()
    if (!content) return

    // Check for unfilled variables before sending
    if (this.hasPlaygroundVariablesOutlet) {
      const variablesController = this.playgroundVariablesOutlet
      if (typeof variablesController.hasUnfilledVariables === "function" && variablesController.hasUnfilledVariables()) {
        const unfilled = typeof variablesController.getUnfilledVariables === "function"
          ? variablesController.getUnfilledVariables()
          : []
        const varList = unfilled.length > 0 ? `: ${unfilled.join(", ")}` : ""
        this.showError(`Please fill in all template variables before sending a message${varList}`)
        return
      }
    }

    // Disable input
    this.setInputState(false)

    // Add user message to UI
    this.addMessage("user", content)
    this.messageInputTarget.value = ""

    // Show typing indicator
    this.showTypingIndicator()

    try {
      // Build request body - get additional context from playground outlet if available
      const requestBody = this.buildRequestBody(content)

      console.log("[PlaygroundConversationController] Sending to URL:", this.sendUrlValue)
      console.log("[PlaygroundConversationController] Request body:", requestBody)

      // Use exact same pattern as playground_save_controller.js which works
      const response = await fetch(this.sendUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify(requestBody)
      })

      console.log("[PlaygroundConversationController] Response status:", response.status)

      const data = await response.json()
      this.hideTypingIndicator()

      if (data.success) {
        this.addMessage("assistant", data.message.content, data.message.tools_used)
        this.updateMessageCount()
      } else {
        this.showError(data.error || "Failed to send message")
      }
    } catch (error) {
      console.error("Error sending message:", error)
      this.hideTypingIndicator()
      this.showError("Network error sending message")
    } finally {
      this.setInputState(true)
      this.messageInputTarget.focus()
    }
  }

  // Build request body, getting context from specialized controller outlets
  buildRequestBody(content) {
    const body = { content }

    // Get prompts from prompt editor controller
    if (this.hasPlaygroundPromptEditorOutlet) {
      const editor = this.playgroundPromptEditorOutlet
      if (typeof editor.getSystemPrompt === "function") {
        body.system_prompt = editor.getSystemPrompt()
      }
      if (typeof editor.getUserPrompt === "function") {
        body.user_prompt = editor.getUserPrompt()
      }
    }

    // Get model config from model config controller
    if (this.hasPlaygroundModelConfigOutlet) {
      const modelConfig = this.playgroundModelConfigOutlet
      if (typeof modelConfig.getModelConfig === "function") {
        body.model_config = modelConfig.getModelConfig()
      }
    }

    // Get variables from variables controller
    if (this.hasPlaygroundVariablesOutlet) {
      const variables = this.playgroundVariablesOutlet
      if (typeof variables.getVariables === "function") {
        body.variables = variables.getVariables()
      }
    }

    console.log("[ConversationController] Built request body:", body)
    return body
  }

  async reset() {
    if (!this.resetUrlValue) return

    try {
      const response = await fetch(this.resetUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({})
      })

      const data = await response.json()

      if (data.success) {
        this.clearMessages()
      } else {
        this.showError(data.error || "Failed to reset conversation")
      }
    } catch (error) {
      console.error("Error resetting conversation:", error)
      this.showError("Network error resetting conversation")
    }
  }

  addMessage(role, content, toolsUsed = []) {
    // Remove empty state if present
    const emptyState = this.messagesContainerTarget.querySelector(".empty-state")
    if (emptyState) emptyState.remove()

    const messageDiv = document.createElement("div")
    messageDiv.className = `message ${role}-message fade-in`

    const avatar = document.createElement("div")
    avatar.className = "message-avatar"
    avatar.innerHTML = role === "user" ? '<i class="bi bi-person"></i>' : '<i class="bi bi-robot"></i>'

    const contentDiv = document.createElement("div")
    contentDiv.className = "message-content"

    const textDiv = document.createElement("div")
    textDiv.className = "message-text"
    textDiv.textContent = content

    contentDiv.appendChild(textDiv)

    // Add tool badges if present
    if (toolsUsed && toolsUsed.length > 0) {
      const toolsDiv = this.createToolBadges(toolsUsed)
      contentDiv.appendChild(toolsDiv)
    }

    const metaDiv = document.createElement("div")
    metaDiv.className = "message-meta"
    metaDiv.innerHTML = `<small class="text-muted">${new Date().toLocaleTimeString()}</small>`
    contentDiv.appendChild(metaDiv)

    messageDiv.appendChild(avatar)
    messageDiv.appendChild(contentDiv)

    this.messagesContainerTarget.appendChild(messageDiv)
    this.scrollToBottom()
  }

  createToolBadges(tools) {
    const toolsDiv = document.createElement("div")
    toolsDiv.className = "tools-used mt-2"

    tools.forEach(tool => {
      const badge = document.createElement("div")
      badge.className = "tool-badge d-inline-flex align-items-center gap-1 px-2 py-1 rounded bg-light border me-1 mb-1"

      const toolType = typeof tool === "string" ? tool : (tool.type || "unknown")
      const iconClass = this.getToolIcon(toolType)

      badge.innerHTML = `<i class="bi ${iconClass}"></i><span class="small">${toolType}</span>`
      toolsDiv.appendChild(badge)
    })

    return toolsDiv
  }

  getToolIcon(toolType) {
    const icons = {
      web_search: "bi-globe text-primary",
      file_search: "bi-file-earmark-search text-info",
      code_interpreter: "bi-code-slash text-success",
      function: "bi-gear text-secondary"
    }
    return icons[toolType] || "bi-tools text-muted"
  }

  showTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.messagesContainerTarget.appendChild(this.typingIndicatorTarget)
      this.typingIndicatorTarget.style.display = "flex"
      this.scrollToBottom()
    }
  }

  hideTypingIndicator() {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.style.display = "none"
    }
  }

  clearMessages() {
    this.messagesContainerTarget.innerHTML = `
      <div class="text-center text-muted py-5 empty-state">
        <i class="bi bi-chat-left-text" style="font-size: 3rem;"></i>
        <p class="mt-3">Send a message to start the conversation</p>
      </div>
    `
    // Re-add typing indicator
    if (this.hasTypingIndicatorTarget) {
      this.messagesContainerTarget.appendChild(this.typingIndicatorTarget)
    }
    this.updateMessageCount()
  }

  scrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
  }

  setInputState(enabled) {
    if (this.hasMessageInputTarget) {
      this.messageInputTarget.disabled = !enabled
    }
    if (this.hasSendButtonTarget) {
      this.sendButtonTarget.disabled = !enabled
    }
  }

  updateMessageCount() {
    if (!this.hasMessageCountTarget || !this.hasMessagesContainerTarget) return

    const messageCount = this.messagesContainerTarget.querySelectorAll(".message").length
    this.messageCountTarget.textContent = `${messageCount} messages`
  }

  showError(message) {
    // Create error toast or alert
    const errorDiv = document.createElement("div")
    errorDiv.className = "alert alert-danger alert-dismissible fade show position-fixed"
    errorDiv.style.cssText = "top: 20px; right: 20px; z-index: 9999; max-width: 400px;"
    errorDiv.innerHTML = `
      <i class="bi bi-exclamation-triangle-fill me-2"></i>${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    document.body.appendChild(errorDiv)

    // Auto-remove after 5 seconds
    setTimeout(() => errorDiv.remove(), 5000)
  }

  // Get CSRF token - exact same as playground_save_controller.js
  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
