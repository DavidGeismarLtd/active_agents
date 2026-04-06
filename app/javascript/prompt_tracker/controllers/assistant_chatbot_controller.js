import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

// Connects to data-controller="assistant-chatbot"
export default class extends Controller {
  static targets = [
    "panel", "fab", "input", "sendButton", "messagesContainer",
    "suggestionsContainer", "loading", "unreadBadge",
    "confirmationModal", "confirmationFunctionName", "confirmationArguments",
    "confirmationMessage", "confirmationArgumentsContainer", "confirmationMessageContainer"
  ]

  static values = {
    sessionId: String,
    context: Object
  }

  connect() {
    console.log("Assistant Chatbot controller connected")
    this.isOpen = false
    this.pendingAction = null
    this.confirmationModalInstance = null
    this.typingMessageElement = null

    // Load initial suggestions
    this.loadSuggestions()
  }

  toggle(event) {
    event?.preventDefault()
    this.isOpen = !this.isOpen

    if (this.isOpen) {
      this.panelTarget.classList.add('open')
      this.fabTarget.classList.add('visually-hidden')
      this.inputTarget.focus()
      this.markAsRead()
    } else {
      this.panelTarget.classList.remove('open')
      this.fabTarget.classList.remove('visually-hidden')
    }
  }

  async sendMessage(event) {
    event.preventDefault()

    const message = this.inputTarget.value.trim()
    if (!message) return

    // Clear input immediately
    this.inputTarget.value = ''

    // Add user message to UI
    this.addMessage('user', message)

    // Show loading
    this.setLoading(true)

    try {
      const response = await this.callAPI('/prompt_tracker/assistant/chat', {
        message: message,
        session_id: this.sessionIdValue,
        context: this.contextValue
      })

      if (response.success) {
        // Add assistant response
        if (response.response) {
          this.addMessage('assistant', response.response, response.links || [])
        }

        // Handle pending action (confirmation required)
        if (response.pending_action) {
          this.pendingAction = response.pending_action

          // Visual indicator in the chat that a tool call is being prepared
          this.addMessage('assistant', this.formatPendingActionSummary(this.pendingAction))

          this.showConfirmationModal(this.pendingAction)
        }

        // Update suggestions
        if (response.suggestions && response.suggestions.length > 0) {
          this.updateSuggestions(response.suggestions)
        }
      } else {
        this.addMessage('assistant', `❌ Error: ${response.error}`)
      }
    } catch (error) {
      console.error('Chat error:', error)
      this.addMessage('assistant', '❌ Sorry, I encountered an error. Please try again.')
    } finally {
      this.setLoading(false)
    }
  }

  async confirmAction(event) {
    event.preventDefault()

    if (!this.pendingAction) return

    // Close modal
    this.getConfirmationModal().hide()

    // Show loading
    this.setLoading(true)

    // Visual indicator in the chat that the tool is being executed
    this.addMessage('assistant', this.formatExecutingActionMessage(this.pendingAction))

    try {
      const response = await this.callAPI('/prompt_tracker/assistant/execute_action', {
        session_id: this.sessionIdValue,
        function_name: this.pendingAction.function_name,
        arguments: this.pendingAction.arguments
      })

      if (response.success) {
	        this.addMessage('assistant', response.response, response.links || [])

	        // If we just executed run_tests, redirect to the tests tab so the user
	        // immediately sees real-time updates.
	        if (this.pendingAction && this.pendingAction.function_name === 'run_tests') {
	          const links = response.links || []
	          const testsLink = links.find(link => link.url && link.url.includes('#tests')) || links[0]
	          if (testsLink && testsLink.url) {
	            if (window.Turbo && typeof Turbo.visit === 'function') {
	              Turbo.visit(testsLink.url)
	            } else {
	              window.location.href = testsLink.url
	            }
	          }
	        }

	        // Update suggestions
	        if (response.suggestions && response.suggestions.length > 0) {
	          this.updateSuggestions(response.suggestions)
	        }
      } else {
        this.addMessage('assistant', `❌ Error: ${response.error}`)
      }
    } catch (error) {
      console.error('Execute action error:', error)
      this.addMessage('assistant', '❌ Failed to execute action. Please try again.')
    } finally {
      this.setLoading(false)
      this.pendingAction = null
    }
  }

  async reset(event) {
    event?.preventDefault()

    if (!confirm('Are you sure you want to reset the conversation?')) {
      return
    }

    try {
      await this.callAPI('/prompt_tracker/assistant/reset', {
        session_id: this.sessionIdValue
      })

      // Clear messages (keep welcome message)
      const messages = this.messagesContainerTarget.querySelectorAll('.user-message, .assistant-message:not(:first-child)')
      messages.forEach(msg => msg.remove())

      // Reload suggestions
      this.loadSuggestions()

    } catch (error) {
      console.error('Reset error:', error)
    }
  }

  useSuggestion(event) {
    event.preventDefault()
    const suggestion = event.currentTarget.dataset.suggestion
    this.inputTarget.value = suggestion
	    this.inputTarget.focus()

	    const form = this.sendButtonTarget?.closest('form')
	    if (form && typeof form.requestSubmit === 'function') {
	      form.requestSubmit()
	    }
  }

  // Private methods

  async callAPI(endpoint, data) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content ||
                      document.querySelector('[name="csrf-token"]')?.content || ''

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify(data)
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return await response.json()
  }

  addMessage(role, content, links = []) {
    const messageHTML = this.buildMessageHTML(role, content, links)
    this.messagesContainerTarget.insertAdjacentHTML('beforeend', messageHTML)
    this.scrollToBottom()
  }

  buildMessageHTML(role, content, links = []) {
    const timestamp = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    const isUser = role === 'user'
    const avatarIcon = isUser ? 'person' : 'robot'
    const bgClass = isUser ? 'bg-primary text-white' : 'bg-light'
    const flexClass = isUser ? 'flex-row-reverse' : ''

    let linksHTML = ''
    if (!isUser && links.length > 0) {
      const linkButtons = links.map(link => {
        const url = this.sanitizeUrl(link.url)
        const text = this.escapeHtml(link.text || '')
        const iconName = link.icon ? this.sanitizeIconName(link.icon) : null
        const iconHtml = iconName ? `<i class="bi bi-${iconName} me-1"></i>` : ''

        return `
        <a href="${url}" class="btn btn-sm btn-outline-primary" target="_blank" rel="noopener noreferrer">
          ${iconHtml}
          ${text}
        </a>
      `
      }).join('')

      linksHTML = `
        <div class="message-links mt-3 pt-3 border-top">
          <div class="d-flex flex-wrap gap-2">
            ${linkButtons}
          </div>
        </div>
      `
    }

    return `
      <div class="${role}-message mb-3">
        <div class="d-flex align-items-start gap-2 ${flexClass}">
          <div class="${role}-avatar ${isUser ? 'bg-secondary' : 'bg-primary'} text-white rounded-circle d-flex align-items-center justify-content-center"
               style="width: 32px; height: 32px; flex-shrink: 0;">
            <i class="bi bi-${avatarIcon}"></i>
          </div>
          <div class="message-content ${bgClass} rounded-3 p-3 flex-grow-1" ${isUser ? 'style="max-width: 85%;"' : ''}>
            <div class="message-text" style="white-space: pre-wrap; word-wrap: break-word;">
              ${this.formatContent(content)}
            </div>
            ${linksHTML}
            <div class="message-timestamp text-muted small mt-2">
              ${timestamp}
            </div>
          </div>
        </div>
      </div>
    `
  }




  formatContent(content) {
    const safeText = this.escapeHtml(content ?? '')

    // Simple markdown-like formatting on escaped text
    return safeText
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\n/g, '<br>')
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
  }

  sanitizeUrl(url) {
    try {
      const parsed = new URL(String(url || ''), window.location.origin)
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
        return parsed.toString()
      }
    } catch (e) {
      // If URL parsing fails, fall back to a safe placeholder
    }

    return '#'
  }

  sanitizeIconName(icon) {
    return String(icon || '').replace(/[^a-z0-9-]/gi, '')
  }

  showConfirmationModal(pendingAction) {
    const modal = this.getConfirmationModal()

    // Set function name
    this.confirmationFunctionNameTarget.textContent = this.humanizeFunctionName(pendingAction.function_name)

    // Set arguments
    this.confirmationArgumentsTarget.innerHTML = this.buildArgumentsHTML(pendingAction.arguments)

    // Set message if available
    if (pendingAction.confirmation_message) {
      this.confirmationMessageTarget.textContent = pendingAction.confirmation_message
    }

    modal.show()
  }

  humanizeFunctionName(name) {
    return name
      .replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase())
  }

  formatPendingActionSummary(pendingAction) {
    const name = this.humanizeFunctionName(pendingAction.function_name)
    const argsSummary = this.summarizeArguments(pendingAction.arguments)

		    const header = `🔧 Planned action: **${name}**`
		    const details = argsSummary ? `\nWith ${argsSummary}.` : ''
		    const footer = "\nWaiting for your confirmation."

		    return `${header}${details}${footer}`.trim()
  }

  formatExecutingActionMessage(pendingAction) {
    const name = this.humanizeFunctionName(pendingAction.function_name)
    const argsSummary = this.summarizeArguments(pendingAction.arguments)

		    const header = `✅ Executing: **${name}**`
		    const details = argsSummary ? `\nWith ${argsSummary}...` : "\nRunning action..."

		    return `${header}${details}`.trim()
  }

  summarizeArguments(args = {}) {
    const entries = Object.entries(args || {})
    if (entries.length === 0) return ''

    return entries.map(([key, value]) => {
      const displayKey = key
        .replace(/_/g, ' ')
        .replace(/\b\w/g, l => l.toUpperCase())
      const displayValue = typeof value === 'object' ? JSON.stringify(value) : String(value)
      return `${displayKey}: ${displayValue}`
    }).join(', ')
  }

  buildArgumentsHTML(args) {
    return Object.entries(args).map(([key, value]) => {
      const displayKey = key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
      const displayValue = typeof value === 'object' ? JSON.stringify(value, null, 2) : value

      return `
        <dt>${displayKey}:</dt>
        <dd>${displayValue}</dd>
      `
    }).join('')
  }

  getConfirmationModal() {
    if (!this.confirmationModalInstance) {
      this.confirmationModalInstance = new Modal(this.confirmationModalTarget)
    }
    return this.confirmationModalInstance
  }

  updateSuggestions(suggestions) {
    const suggestionsHTML = suggestions.map(suggestion => `
      <button type="button"
              class="btn btn-sm btn-outline-secondary"
              data-action="click->assistant-chatbot#useSuggestion"
              data-suggestion="${suggestion}">
        ${suggestion}
      </button>
    `).join('')

    this.suggestionsContainerTarget.innerHTML = `
      <div class="d-flex flex-wrap gap-2">
        ${suggestionsHTML}
      </div>
    `
  }

  async loadSuggestions() {
    try {
      const response = await this.callAPI('/prompt_tracker/assistant/suggestions', {
        context: this.contextValue
      })

      if (response.success && response.suggestions) {
        this.updateSuggestions(response.suggestions)
      }
    } catch (error) {
      console.error('Load suggestions error:', error)
    }
  }

  scrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
  }

  setLoading(loading) {
    if (loading) {
      this.sendButtonTarget.disabled = true
      this.inputTarget.disabled = true
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.remove('visually-hidden')
      }
      this.showTypingIndicator()
    } else {
      this.sendButtonTarget.disabled = false
      this.inputTarget.disabled = false
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add('visually-hidden')
      }
      this.hideTypingIndicator()
      this.inputTarget.focus()
    }
  }

  markAsRead() {
    if (this.hasUnreadBadgeTarget) {
      this.unreadBadgeTarget.classList.add('visually-hidden')
    }
  }

	  // Typing indicator: show "..." assistant bubble while waiting for responses
	  showTypingIndicator() {
	    if (this.typingMessageElement) return

	    const messageHTML = this.buildMessageHTML('assistant', '...')
	    this.messagesContainerTarget.insertAdjacentHTML('beforeend', messageHTML)
	    this.typingMessageElement = this.messagesContainerTarget.lastElementChild
	    if (this.typingMessageElement) {
	      this.typingMessageElement.classList.add('assistant-typing-message')
	    }
	    this.scrollToBottom()
	  }

	  hideTypingIndicator() {
	    if (!this.typingMessageElement) return
	    this.typingMessageElement.remove()
	    this.typingMessageElement = null
	  }
}
