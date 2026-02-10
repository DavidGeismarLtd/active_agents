import { Controller } from "@hotwired/stimulus"

/**
 * Playground Preview Stimulus Controller
 *
 * @description
 * Manages live preview rendering of prompts by fetching rendered output from the server.
 * Implements debounced updates, incomplete syntax detection, and error handling for a smooth
 * preview experience.
 *
 * @responsibilities
 * - Render live preview of system and user prompts with variables substituted
 * - Debounce preview updates (500ms delay) to avoid excessive server requests
 * - Detect incomplete Liquid/Mustache syntax and show "Typing..." indicator
 * - Handle preview errors and display user-friendly error messages
 * - Update engine badge (Liquid) when preview renders successfully
 * - Show loading states during preview fetch
 *
 * @targets
 * - previewContainer: Container for rendered preview HTML
 * - previewError: Error message display area
 * - engineBadge: Badge showing template engine (Liquid)
 * - refreshBtn: Manual refresh button
 * - previewStatus: Loading status indicator
 *
 * @values
 * - previewUrl (String): Server endpoint for preview rendering
 *
 * @outlets
 * - playground-prompt-editor: Editor controller to get prompt data
 * - playground-variables: Variables controller to get variable values
 *
 * @events_dispatched
 * None - preview is read-only display
 *
 * @events_listened_to
 * - playground-prompt-editor:promptChanged (Stimulus): Triggers debounced preview update
 * - playground-variables:changed (Stimulus): Triggers debounced preview update when variables change
 *
 * @communication_pattern
 * Listens for `promptChanged` events from the prompt editor controller and `changed` events
 * from the variables controller. When received, triggers a debounced preview update.
 * Calls outlet methods (getSystemPrompt, getUserPrompt, getVariables) to collect data for
 * preview rendering. Sends data to server via fetch and displays the rendered result.
 *
 * @public_methods
 * - refreshPreview(): Manually refresh preview (called by coordinator keyboard shortcut)
 * - updatePreview(): Immediately update preview (bypasses debounce)
 *
 * @example
 * // In view:
 * <div data-controller="playground-preview"
 *      data-playground-preview-preview-url-value="/preview"
 *      data-playground-preview-playground-prompt-editor-outlet="#editor-container"
 *      data-playground-preview-playground-variables-outlet="#variables-container">
 *   <div data-playground-preview-target="previewContainer"></div>
 *   <div data-playground-preview-target="previewError"></div>
 * </div>
 */
export default class extends Controller {
  static targets = [
    "previewContainer",
    "previewError",
    "engineBadge",
    "refreshBtn",
    "previewStatus"
  ]

  static values = {
    previewUrl: String
  }

  static outlets = ["playground-prompt-editor", "playground-variables"]

  connect() {
    console.log('[PlaygroundPreviewController] ========== CONNECT ==========')
    console.log('[PlaygroundPreviewController] Element:', this.element)
    console.log('[PlaygroundPreviewController] Preview URL:', this.previewUrlValue)
    console.log('[PlaygroundPreviewController] Has prompt editor outlet?', this.hasPlaygroundPromptEditorOutlet)
    console.log('[PlaygroundPreviewController] Has variables outlet?', this.hasPlaygroundVariablesOutlet)

    this.debounceTimer = null
    this.debounceDelay = 500 // ms

    // Initial preview
    this.updatePreview()

    console.log('[PlaygroundPreviewController] ========== CONNECT COMPLETE ==========')
  }

  /**
   * Action: Called when prompt content changes (via data-action)
   */
  onPromptChanged(event) {
    console.log('[PlaygroundPreviewController] onPromptChanged:', event.detail)
    this.debouncedUpdatePreview()
  }

  /**
   * Action: Called when variables change (via data-action)
   */
  onVariablesChanged(event) {
    console.log('[PlaygroundPreviewController] onVariablesChanged:', event.detail)
    this.debouncedUpdatePreview()
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  // Action: Refresh preview
  refreshPreview() {
    console.log('[PlaygroundPreviewController] refreshPreview() called')
    this.updatePreview()
  }

  // Debounced preview update
  debouncedUpdatePreview() {
    console.log('[PlaygroundPreviewController] debouncedUpdatePreview() called')
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => {
      this.updatePreview()
    }, this.debounceDelay)
  }

  // Update preview
  async updatePreview() {
    console.log('[PlaygroundPreviewController] ========== UPDATE PREVIEW ==========')

    if (!this.hasPlaygroundPromptEditorOutlet) {
      console.log('[PlaygroundPreviewController] No prompt editor outlet - cannot get prompts')
      return
    }

    const systemPrompt = this.playgroundPromptEditorOutlet.getSystemPrompt()
    const userPrompt = this.playgroundPromptEditorOutlet.getUserPrompt()
    const variables = this.hasPlaygroundVariablesOutlet
      ? this.playgroundVariablesOutlet.getVariables()
      : {}

    console.log('[PlaygroundPreviewController] System prompt length:', systemPrompt.length)
    console.log('[PlaygroundPreviewController] User prompt length:', userPrompt.length)
    console.log('[PlaygroundPreviewController] Variables:', variables)

    if (!userPrompt.trim()) {
      this.previewContainerTarget.innerHTML = '<p class="text-muted">Enter a user prompt to see preview...</p>'
      this.previewErrorTarget.style.display = 'none'
      console.log('[PlaygroundPreviewController] No user prompt - showing placeholder')
      return
    }

    // Check for incomplete Liquid/Mustache syntax
    if (this.hasIncompleteSyntax(userPrompt) || this.hasIncompleteSyntax(systemPrompt)) {
      this.previewContainerTarget.innerHTML = '<p class="text-muted"><i class="bi bi-pencil"></i> Typing...</p>'
      this.previewErrorTarget.style.display = 'none'
      console.log('[PlaygroundPreviewController] Incomplete syntax detected - showing typing indicator')
      return
    }

    // Show loading state
    this.showPreviewLoading(true)

    try {
      console.log('[PlaygroundPreviewController] Fetching preview from:', this.previewUrlValue)

      const response = await fetch(this.previewUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          system_prompt: systemPrompt,
          user_prompt: userPrompt,
          variables: variables
        })
      })

      console.log('[PlaygroundPreviewController] Response status:', response.status)

      if (!response.ok) {
        const text = await response.text()
        console.error('[PlaygroundPreviewController] Server error response:', text)
        this.showPreviewError([`Server error (${response.status}): ${response.statusText}`])
        this.showPreviewLoading(false)
        return
      }

      const contentType = response.headers.get('content-type')
      if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text()
        console.error('[PlaygroundPreviewController] Non-JSON response:', text)
        this.showPreviewError(['Server returned non-JSON response. Check console for details.'])
        this.showPreviewLoading(false)
        return
      }

      const data = await response.json()
      console.log('[PlaygroundPreviewController] Preview data received:', data)

      if (data.success) {
        // Build preview HTML with both system and user prompts
        let previewHtml = ''

        if (data.rendered_system) {
          previewHtml += `<div class="mb-3">
            <div class="badge bg-secondary mb-2">System Prompt</div>
            <div class="border-start border-3 border-secondary ps-3">${this.escapeHtml(data.rendered_system)}</div>
          </div>`
        }

        previewHtml += `<div>
          <div class="badge bg-primary mb-2">User Prompt</div>
          <div class="border-start border-3 border-primary ps-3">${this.escapeHtml(data.rendered_user)}</div>
        </div>`

        this.previewContainerTarget.innerHTML = previewHtml
        this.previewErrorTarget.style.display = 'none'
        this.updateEngineBadge()

        // Notify editor about detected variables
        if (data.variables_detected && this.hasPlaygroundEditorOutlet) {
          this.playgroundEditorOutlet.updateVariablesFromDetection(data.variables_detected)
        }

        console.log('[PlaygroundPreviewController] Preview rendered successfully')
      } else {
        console.error('[PlaygroundPreviewController] Preview failed:', data.errors)
        this.showPreviewError(data.errors || ['Unknown error'])
      }

      this.showPreviewLoading(false)
    } catch (error) {
      console.error('[PlaygroundPreviewController] Network error:', error)
      this.showPreviewError([`Network error: ${error.message}`])
      this.showPreviewLoading(false)
    }

    console.log('[PlaygroundPreviewController] ========== UPDATE PREVIEW COMPLETE ==========')
  }

  // Check for incomplete Liquid/Mustache syntax
  hasIncompleteSyntax(template) {
    // Check for incomplete {{ or {% tags
    const openBraces = (template.match(/\{\{/g) || []).length
    const closeBraces = (template.match(/\}\}/g) || []).length
    const openTags = (template.match(/\{%/g) || []).length
    const closeTags = (template.match(/%\}/g) || []).length

    return openBraces !== closeBraces || openTags !== closeTags
  }

  // Update engine badge
  updateEngineBadge() {
    if (this.hasEngineBadgeTarget) {
      this.engineBadgeTarget.textContent = 'Liquid'
      console.log('[PlaygroundPreviewController] Engine badge updated')
    }
  }

  // Show preview error
  showPreviewError(errors) {
    console.log('[PlaygroundPreviewController] Showing preview errors:', errors)
    this.previewErrorTarget.innerHTML = '<strong>Preview Error:</strong><br>' + errors.join('<br>')
    this.previewErrorTarget.style.display = 'block'
    this.previewContainerTarget.innerHTML = '<p class="text-muted">Fix errors to see preview...</p>'
  }

  // Show/hide preview loading state
  showPreviewLoading(isLoading) {
    console.log('[PlaygroundPreviewController] Loading state:', isLoading)

    if (this.hasPreviewStatusTarget) {
      if (isLoading) {
        this.previewStatusTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Rendering preview...'
        this.previewStatusTarget.style.display = ''
      } else {
        this.previewStatusTarget.style.display = 'none'
      }
    }

    if (this.hasRefreshBtnTarget) {
      this.refreshBtnTarget.disabled = isLoading
    }
  }

  // Get CSRF token
  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  // Escape HTML
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
