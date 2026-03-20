import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="prompt-tracker--agent-chat"
export default class extends Controller {
  static targets = ["messages", "input", "form", "sendButton", "typingIndicator"]
  static values = { slug: String }

  connect() {
    console.log("[AgentChatController] Connected with slug:", this.slugValue)
    this.conversationId = null
    this.scrollToBottom()
  }

  async sendMessage(event) {
    event.preventDefault()

    const message = this.inputTarget.value.trim()
    if (!message) return

    // Add user message to UI
    this.addMessage("user", message)

    // Clear input and disable form
    this.inputTarget.value = ""
    this.setLoading(true)

    try {
      // Send message to API
      const response = await this.callChatAPI(message)

      // Show function calls if any
      if (response.function_calls && response.function_calls.length > 0) {
        this.addFunctionCallsMessage(response.function_calls)
      }

      // Add assistant response to UI
      this.addMessage("assistant", response.response)

      // Store conversation ID for follow-up messages
      this.conversationId = response.conversation_id

    } catch (error) {
      console.error("Chat error:", error)
      this.addMessage("assistant", "Sorry, I encountered an error. Please try again.", true)
    } finally {
      this.setLoading(false)
      this.inputTarget.focus()
    }
  }

  async callChatAPI(message) {
    const url = `/agents/${this.slugValue}/chat`
    const body = {
      message: message
    }

    // Include conversation ID if we have one
    if (this.conversationId) {
      body.conversation_id = this.conversationId
    }

    // Get CSRF token from meta tag
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const headers = {
      "Content-Type": "application/json",
      "Accept": "application/json"
    }

    if (csrfToken) {
      headers["X-CSRF-Token"] = csrfToken
    }

    const response = await fetch(url, {
      method: "POST",
      headers: headers,
      body: JSON.stringify(body)
    })

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: "Request failed" }))
      throw new Error(error.error || "Request failed")
    }

    return await response.json()
  }

  addMessage(role, content, isError = false) {
    const messageDiv = document.createElement("div")
    messageDiv.className = `message ${role}`

    const avatar = document.createElement("div")
    avatar.className = "message-avatar"
    avatar.textContent = role === "user" ? "You" : "AI"

    const contentDiv = document.createElement("div")
    contentDiv.className = "message-content"
    if (isError) {
      contentDiv.style.background = "#dc3545"
      contentDiv.style.color = "white"
    }

    const paragraph = document.createElement("p")
    paragraph.className = "mb-0"
    paragraph.textContent = content

    contentDiv.appendChild(paragraph)
    messageDiv.appendChild(avatar)
    messageDiv.appendChild(contentDiv)

    // Insert before typing indicator
    const typingMessage = this.typingIndicatorTarget.closest(".message")
    this.messagesTarget.insertBefore(messageDiv, typingMessage)

    this.scrollToBottom()
  }

  addFunctionCallsMessage(functionCalls) {
    const messageDiv = document.createElement("div")
    messageDiv.className = "message system"
    messageDiv.style.opacity = "0.8"

    const avatar = document.createElement("div")
    avatar.className = "message-avatar"
    avatar.textContent = "🔧"
    avatar.style.background = "#6c757d"

    const contentDiv = document.createElement("div")
    contentDiv.className = "message-content"
    contentDiv.style.background = "#f8f9fa"
    contentDiv.style.color = "#495057"
    contentDiv.style.fontSize = "0.9em"

    const title = document.createElement("div")
    title.style.fontWeight = "600"
    title.style.marginBottom = "0.5rem"
    title.textContent = `🔧 Called ${functionCalls.length} function(s):`

    contentDiv.appendChild(title)

    functionCalls.forEach((call, index) => {
      const funcName = call.name || call.function?.name || "unknown"
      const funcArgs = call.arguments || call.function?.arguments || {}

      const funcDiv = document.createElement("div")
      funcDiv.style.marginBottom = index < functionCalls.length - 1 ? "0.5rem" : "0"

      const funcTitle = document.createElement("div")
      funcTitle.style.fontWeight = "500"
      funcTitle.textContent = `${index + 1}. ${funcName}()`

      const funcArgsDiv = document.createElement("div")
      funcArgsDiv.style.fontSize = "0.85em"
      funcArgsDiv.style.marginLeft = "1rem"
      funcArgsDiv.style.color = "#6c757d"

      // Format arguments
      const argsStr = typeof funcArgs === 'string'
        ? funcArgs
        : JSON.stringify(funcArgs, null, 2)
      funcArgsDiv.textContent = argsStr

      funcDiv.appendChild(funcTitle)
      if (Object.keys(funcArgs).length > 0) {
        funcDiv.appendChild(funcArgsDiv)
      }

      contentDiv.appendChild(funcDiv)
    })

    messageDiv.appendChild(avatar)
    messageDiv.appendChild(contentDiv)

    // Insert before typing indicator
    const typingMessage = this.typingIndicatorTarget.closest(".message")
    this.messagesTarget.insertBefore(messageDiv, typingMessage)

    this.scrollToBottom()
  }

  setLoading(loading) {
    this.sendButtonTarget.disabled = loading
    this.inputTarget.disabled = loading

    if (loading) {
      this.typingIndicatorTarget.classList.add("active")
    } else {
      this.typingIndicatorTarget.classList.remove("active")
    }

    this.scrollToBottom()
  }

  scrollToBottom() {
    // Use setTimeout to ensure DOM has updated
    setTimeout(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }, 100)
  }
}
