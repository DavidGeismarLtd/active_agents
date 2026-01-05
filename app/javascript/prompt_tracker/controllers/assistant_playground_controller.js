import { Controller } from "@hotwired/stimulus"
import { Toast } from "bootstrap"

// Connects to data-controller="assistant-playground"
export default class extends Controller {
  static targets = [
    "messagesContainer",
    "messageInput",
    "sendButton",
    "threadId",
    "newThreadButton",
    "name",
    "description",
    "instructions",
    "charCount",
    "model",
    "toolCheckbox",
    "responseFormat",
    "temperature",
    "temperatureValue",
    "topP",
    "topPValue",
    "saveButton",
    "saveButtonText",
    "saveStatus",
    "toast",
    "toastBody",
    // Functions section target for accessing nested function-editor controller
    "functionsSection"
  ]

  static values = {
    assistantId: String,
    isNew: Boolean,
    createUrl: String,
    updateUrl: String,
    sendMessageUrl: String,
    createThreadUrl: String,
    loadMessagesUrl: String
  }

  connect() {
    console.log("Assistant Playground controller connected")

    // Initialize character counter
    this.updateCharCount()

    // Setup auto-save debouncing
    this.saveTimeout = null
    this.setupAutoSave()

    // Load existing thread messages if not new
    if (!this.isNewValue && this.hasThreadIdTarget) {
      this.loadMessages()
    }

    // Setup keyboard shortcuts
    this.setupKeyboardShortcuts()
  }

  disconnect() {
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }
  }

  // ========================================
  // Function Editor Event Handlers
  // ========================================

  handleFunctionsChanged(event) {
    // Store the latest functions from the function-editor controller
    // Note: We intentionally do NOT auto-save here to avoid unexpected saves
    // The user should explicitly click "Save" to persist function changes
    this.functions = event.detail.functions || []
  }

  handleNotification(event) {
    const { type, message } = event.detail
    if (type === "error") {
      this.showError(message)
    } else if (type === "success") {
      this.showSuccess(message)
    }
  }

  getFunctions() {
    // Try to get functions from the function-editor controller
    if (this.hasFunctionsSectionTarget) {
      const functionEditorController = this.application.getControllerForElementAndIdentifier(
        this.functionsSectionTarget,
        "function-editor"
      )
      if (functionEditorController) {
        return functionEditorController.getFunctions()
      }
    }
    // Fallback to stored functions
    return this.functions || []
  }

  // ========================================
  // Thread Management
  // ========================================

  async createNewThread() {
    if (this.isNewValue) {
      this.showError("Please save the assistant first")
      return
    }

    try {
      const response = await fetch(this.createThreadUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success) {
        this.currentThreadId = data.thread_id
        this.threadIdTarget.textContent = `Thread: ${data.thread_id.substring(0, 8)}...`
        this.clearMessages()
        this.showSuccess("New thread created")
      } else {
        this.showError(data.error || "Failed to create thread")
      }
    } catch (error) {
      console.error("Error creating thread:", error)
      this.showError("Network error creating thread")
    }
  }

  async loadMessages() {
    if (!this.currentThreadId) return

    try {
      const url = `${this.loadMessagesUrlValue}?thread_id=${this.currentThreadId}`
      const response = await fetch(url, {
        headers: {
          "X-CSRF-Token": this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success && data.messages.length > 0) {
        this.clearMessages()
        data.messages.forEach(msg => {
          this.addMessage(msg.role, msg.content, msg.created_at)
        })
      }
    } catch (error) {
      console.error("Error loading messages:", error)
    }
  }

  // ========================================
  // Message Handling
  // ========================================

  async sendMessage(event) {
    event.preventDefault()

    if (this.isNewValue) {
      this.showError("Please save the assistant first")
      return
    }

    const content = this.messageInputTarget.value.trim()
    if (!content) return

    // Disable input
    this.messageInputTarget.disabled = true
    this.sendButtonTarget.disabled = true

    // Add user message to UI
    this.addMessage("user", content)
    this.messageInputTarget.value = ""

    // Show typing indicator
    this.showTypingIndicator()

    try {
      const response = await fetch(this.sendMessageUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({
          assistant_id: this.assistantIdValue,
          thread_id: this.currentThreadId,
          content: content
        })
      })

      const data = await response.json()

      this.hideTypingIndicator()

      if (data.success) {
        // Update thread ID if it was auto-created
        if (data.thread_id && !this.currentThreadId) {
          this.currentThreadId = data.thread_id
          this.threadIdTarget.textContent = `Thread: ${data.thread_id.substring(0, 8)}...`
        }

        // Add assistant message
        this.addMessage("assistant", data.message.content, data.message.created_at)

        // Show usage info if available
        if (data.usage) {
          console.log("Token usage:", data.usage)
        }
      } else {
        this.showError(data.error || "Failed to send message")
      }
    } catch (error) {
      console.error("Error sending message:", error)
      this.hideTypingIndicator()
      this.showError("Network error sending message")
    } finally {
      // Re-enable input
      this.messageInputTarget.disabled = false
      this.sendButtonTarget.disabled = false
      this.messageInputTarget.focus()
    }
  }

  addMessage(role, content, createdAt = null) {
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

    const metaDiv = document.createElement("div")
    metaDiv.className = "message-meta"

    const timeSpan = document.createElement("small")
    timeSpan.className = "text-muted"
    timeSpan.textContent = createdAt ? new Date(createdAt).toLocaleTimeString() : new Date().toLocaleTimeString()

    metaDiv.appendChild(timeSpan)
    contentDiv.appendChild(textDiv)
    contentDiv.appendChild(metaDiv)

    messageDiv.appendChild(avatar)
    messageDiv.appendChild(contentDiv)

    // Remove empty state message if present
    const emptyState = this.messagesContainerTarget.querySelector(".text-center.text-muted")
    if (emptyState) {
      emptyState.remove()
    }

    this.messagesContainerTarget.appendChild(messageDiv)
    this.scrollToBottom()
  }

  showTypingIndicator() {
    const indicator = this.messagesContainerTarget.querySelector(".loading")
    if (indicator) {
      // Move indicator to the end of the messages container
      this.messagesContainerTarget.appendChild(indicator)
      indicator.style.display = "flex"
      this.scrollToBottom()
    }
  }

  hideTypingIndicator() {
    const indicator = this.messagesContainerTarget.querySelector(".loading")
    if (indicator) {
      indicator.style.display = "none"
    }
  }

  clearMessages() {
    this.messagesContainerTarget.innerHTML = `
      <div class="text-center text-muted py-5">
        <i class="bi bi-chat-left-text" style="font-size: 3rem;"></i>
        <p class="mt-3">Start a conversation to test your assistant</p>
      </div>
      <div class="message assistant-message loading" style="display: none;">
        <div class="message-avatar">
          <i class="bi bi-robot"></i>
        </div>
        <div class="message-content">
          <div class="typing-indicator">
            <span></span><span></span><span></span>
          </div>
        </div>
      </div>
    `
  }

  scrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
  }

  // ========================================
  // Assistant Configuration
  // ========================================

  async saveAssistant() {
    const assistantData = this.getAssistantData()

    // Validate required fields
    if (!assistantData.name) {
      this.showError("Name is required")
      return
    }

    // Show saving state
    this.setSaveStatus("saving", "Saving...")
    this.saveButtonTarget.classList.add("btn-loading")
    this.saveButtonTarget.disabled = true

    try {
      const url = this.isNewValue ? this.createUrlValue : this.updateUrlValue
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({ assistant: assistantData })
      })

      const data = await response.json()

      if (data.success) {
        this.setSaveStatus("saved", `Saved at ${data.last_saved_at || new Date().toLocaleTimeString()}`)

        // If this was a new assistant, redirect to edit mode
        if (this.isNewValue && data.redirect_url) {
          window.location.href = data.redirect_url
        } else {
          // Update assistant ID if needed
          if (data.assistant_id) {
            this.assistantIdValue = data.assistant_id
          }
          this.showSuccess("Assistant saved successfully")
        }
      } else {
        this.setSaveStatus("error", "Save failed")
        this.showError(data.error || "Failed to save assistant")
      }
    } catch (error) {
      console.error("Error saving assistant:", error)
      this.setSaveStatus("error", "Save failed")
      this.showError("Network error saving assistant")
    } finally {
      this.saveButtonTarget.classList.remove("btn-loading")
      this.saveButtonTarget.disabled = false
    }
  }

  getAssistantData() {
    const tools = []
    this.toolCheckboxTargets.forEach(checkbox => {
      if (checkbox.checked) {
        tools.push(checkbox.value)
      }
    })

    return {
      name: this.nameTarget.value,
      description: this.descriptionTarget.value,
      instructions: this.instructionsTarget.value,
      model: this.modelTarget.value,
      tools: tools,
      functions: this.getFunctions(),
      temperature: parseFloat(this.temperatureTarget.value),
      top_p: parseFloat(this.topPTarget.value),
      response_format: this.responseFormatTarget.value
    }
  }

  setupAutoSave() {
    // Auto-save on configuration changes (debounced)
    const inputs = [
      this.nameTarget,
      this.descriptionTarget,
      this.instructionsTarget,
      this.modelTarget,
      this.responseFormatTarget,
      this.temperatureTarget,
      this.topPTarget
    ]

    inputs.forEach(input => {
      input.addEventListener("input", () => {
        if (!this.isNewValue) {
          this.debouncedSave()
        }
      })
    })

    this.toolCheckboxTargets.forEach(checkbox => {
      checkbox.addEventListener("change", () => {
        if (!this.isNewValue) {
          this.debouncedSave()
        }
      })
    })

    // Update range value displays
    this.temperatureTarget.addEventListener("input", () => {
      this.temperatureValueTarget.textContent = this.temperatureTarget.value
    })

    this.topPTarget.addEventListener("input", () => {
      this.topPValueTarget.textContent = this.topPTarget.value
    })

    // Update character count
    this.instructionsTarget.addEventListener("input", () => {
      this.updateCharCount()
    })
  }

  debouncedSave() {
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }

    this.setSaveStatus("saving", "Saving...")

    this.saveTimeout = setTimeout(() => {
      this.saveAssistant()
    }, 3000) // 3 second debounce
  }

  updateCharCount() {
    if (this.hasInstructionsTarget && this.hasCharCountTarget) {
      this.charCountTarget.textContent = this.instructionsTarget.value.length
    }
  }

  // ========================================
  // UI Helpers
  // ========================================

  setSaveStatus(status, message) {
    if (!this.hasSaveStatusTarget) return

    this.saveStatusTarget.className = `text-muted small text-center save-status-${status}`
    this.saveStatusTarget.innerHTML = `<i class="bi bi-${this.getStatusIcon(status)}"></i> ${message}`
  }

  getStatusIcon(status) {
    const icons = {
      saving: "clock",
      saved: "check-circle",
      error: "exclamation-circle"
    }
    return icons[status] || "clock"
  }

  showSuccess(message) {
    this.showToast(message, "success")
  }

  showError(message) {
    this.showToast(message, "error")
  }

  showToast(message, type = "success") {
    if (!this.hasToastTarget || !this.hasToastBodyTarget) {
      console.log(`${type}:`, message)
      return
    }

    // Set toast styling based on type
    const bgClass = type === "success" ? "bg-success" : "bg-danger"
    this.toastTarget.className = `toast align-items-center text-white ${bgClass} border-0`

    // Set icon based on type
    const icon = type === "success" ? "check-circle-fill" : "exclamation-triangle-fill"
    this.toastBodyTarget.innerHTML = `<i class="bi bi-${icon} me-2"></i>${message}`

    // Show the toast using Bootstrap's Toast API
    const bsToast = new Toast(this.toastTarget, {
      autohide: true,
      delay: 3000
    })
    bsToast.show()
  }

  setupKeyboardShortcuts() {
    this.messageInputTarget.addEventListener("keydown", (e) => {
      // Submit on Enter (without Shift)
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        this.sendMessage(e)
      }
    })
  }

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
