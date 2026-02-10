import { Controller } from "@hotwired/stimulus"

/**
 * Playground Save Stimulus Controller
 *
 * @description
 * Manages all save operations including save draft, update existing version, and save as new version.
 * Handles validation, data collection from other controllers, server communication, and user feedback
 * via alerts and loading states.
 *
 * @responsibilities
 * - Handle save draft, update, and new version operations
 * - Validate prompt name and check for unfilled variables
 * - Collect data from editor, model-config, and response-schema controllers
 * - Auto-generate slug from prompt name
 * - Show loading states on save buttons during save operations
 * - Display success/error alerts with auto-dismiss
 * - Redirect to new URL after successful save
 *
 * @targets
 * - promptName: Prompt name input field
 * - promptSlug: Prompt slug input field
 * - saveDraftBtn: Save draft button
 * - saveUpdateBtn: Update existing version button
 * - saveNewVersionBtn: Save as new version button
 * - alertContainer: Container for alert messages
 * - saveStatus: Save status indicator
 *
 * @values
 * - saveDraftUrl (String): URL for save draft endpoint
 * - saveUpdateUrl (String): URL for update endpoint
 * - saveNewVersionUrl (String): URL for new version endpoint
 * - promptId (String): Current prompt ID
 * - versionId (String): Current version ID
 *
 * @outlets
 * - playground-prompt-editor: To get prompts
 * - playground-variables: To get variables
 * - playground-model-config: To get model configuration
 * - playground-response-schema: To get response schema (optional)
 *
 * @events_dispatched
 * None - save is a terminal operation
 *
 * @events_listened_to
 * - click (saveDraftBtn): Save draft action
 * - click (saveUpdateBtn): Update action
 * - click (saveNewVersionBtn): New version action
 * - input (promptName): Auto-generate slug
 * - input (promptSlug): Mark as manually edited
 *
 * @communication_pattern
 * Calls public methods on outlet controllers to collect data:
 * - promptEditor.getSystemPrompt(), getUserPrompt()
 * - variables.getVariables(), hasUnfilledVariables()
 * - modelConfig.getModelConfig()
 * - responseSchema.getResponseSchema() (if available)
 * Sends collected data to server via fetch and handles response.
 *
 * @public_methods
 * - showAlert(message, type): Display alert message (called by coordinator)
 *
 * @example
 * // In view:
 * <div data-controller="playground-save"
 *      data-playground-save-save-draft-url-value="/save_draft"
 *      data-playground-save-playground-prompt-editor-outlet="#editor"
 *      data-playground-save-playground-variables-outlet="#variables"
 *      data-playground-save-playground-model-config-outlet="#model-config">
 *   <button data-playground-save-target="saveDraftBtn"
 *           data-action="click->playground-save#saveDraft">Save Draft</button>
 * </div>
 */
export default class extends Controller {
  static targets = [
    "promptName",
    "promptSlug",
    "saveDraftBtn",
    "saveUpdateBtn",
    "saveNewVersionBtn",
    "alertContainer",
    "saveStatus"
  ]

  static values = {
    saveUrl: String,
    promptId: String,
    promptName: String,
    versionId: String
  }

  static outlets = ["playground-prompt-editor", "playground-variables", "playground-model-config", "playground-response-schema"]

  connect() {
    console.log('[PlaygroundSaveController] ========== CONNECT ==========')
    console.log('[PlaygroundSaveController] Element:', this.element)
    console.log('[PlaygroundSaveController] Prompt ID:', this.promptIdValue)
    console.log('[PlaygroundSaveController] Version ID:', this.versionIdValue)
    console.log('[PlaygroundSaveController] Save URL:', this.saveUrlValue)
    console.log('[PlaygroundSaveController] Has prompt editor outlet?', this.hasPlaygroundPromptEditorOutlet)
    console.log('[PlaygroundSaveController] Has variables outlet?', this.hasPlaygroundVariablesOutlet)
    console.log('[PlaygroundSaveController] Has model-config outlet?', this.hasPlaygroundModelConfigOutlet)
    console.log('[PlaygroundSaveController] ========== CONNECT COMPLETE ==========')
  }

  // Action: Save draft
  async saveDraft(event) {
    console.log('[PlaygroundSaveController] ========== SAVE DRAFT ==========')
    event.preventDefault()
    await this.performSave('draft')
  }

  // Action: Save update
  async saveUpdate(event) {
    console.log('[PlaygroundSaveController] ========== SAVE UPDATE ==========')
    event.preventDefault()
    await this.performSave('update')
  }

  // Action: Save new version
  async saveNewVersion(event) {
    console.log('[PlaygroundSaveController] ========== SAVE NEW VERSION ==========')
    event.preventDefault()
    await this.performSave('new_version')
  }

  // Perform save operation
  async performSave(saveAction) {
    console.log('[PlaygroundSaveController] performSave() called with action:', saveAction)

    // Validate required outlets
    if (!this.hasPlaygroundPromptEditorOutlet) {
      console.error('[PlaygroundSaveController] Missing prompt editor outlet')
      this.showAlert('Missing prompt editor controller', 'danger')
      return
    }

    if (!this.hasPlaygroundModelConfigOutlet) {
      console.error('[PlaygroundSaveController] Missing model-config outlet')
      this.showAlert('Missing model-config controller', 'danger')
      return
    }

    // Get prompt name - from input target (standalone mode) or value (editing existing prompt)
    const promptName = this.hasPromptNameTarget
      ? this.promptNameTarget.value.trim()
      : (this.promptNameValue || '')
    console.log('[PlaygroundSaveController] Prompt name:', promptName)

    if (!promptName) {
      console.error('[PlaygroundSaveController] Prompt name is required')
      this.showAlert('Prompt name is required', 'warning')
      return
    }

    // Check for unfilled variables
    const hasUnfilled = this.hasPlaygroundVariablesOutlet &&
      this.playgroundVariablesOutlet.hasUnfilledVariables()
    if (hasUnfilled) {
      const unfilled = this.playgroundVariablesOutlet.getUnfilledVariables()
      console.warn('[PlaygroundSaveController] Unfilled variables:', unfilled)

      const proceed = confirm(
        `The following variables are not filled:\n${unfilled.join(', ')}\n\nDo you want to save anyway?`
      )

      if (!proceed) {
        console.log('[PlaygroundSaveController] User cancelled save due to unfilled variables')
        return
      }
    }

    // Collect data - flat structure as expected by backend
    const data = {
      prompt_name: promptName,
      prompt_slug: this.hasPromptSlugTarget ? this.promptSlugTarget.value : '',
      system_prompt: this.playgroundPromptEditorOutlet.getSystemPrompt(),
      user_prompt: this.playgroundPromptEditorOutlet.getUserPrompt(),
      template_variables: this.hasPlaygroundVariablesOutlet
        ? this.playgroundVariablesOutlet.getVariables()
        : {},
      model_config: this.playgroundModelConfigOutlet.getModelConfig(),
      save_action: saveAction
    }

    // Add response schema if available
    if (this.hasPlaygroundResponseSchemaOutlet) {
      const responseSchema = this.playgroundResponseSchemaOutlet.getResponseSchema()
      if (responseSchema) {
        data.response_schema = responseSchema
      }
    }
    console.log('[PlaygroundSaveController] Save data:', data)

    // Use single save URL for all actions
    const url = this.saveUrlValue
    console.log('[PlaygroundSaveController] Save URL:', url)

    if (!url) {
      console.error('[PlaygroundSaveController] No save URL configured')
      this.showAlert('Save URL not configured', 'danger')
      return
    }

    // Show loading state
    this.showSaveLoading(saveAction, true)

    try {
      console.log('[PlaygroundSaveController] Sending save request...')

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify(data)
      })

      console.log('[PlaygroundSaveController] Response status:', response.status)

      if (!response.ok) {
        const text = await response.text()
        console.error('[PlaygroundSaveController] Server error response:', text)
        this.showAlert(`Server error (${response.status}): ${response.statusText}`, 'danger')
        this.showSaveLoading(saveAction, false)
        return
      }

      const result = await response.json()
      console.log('[PlaygroundSaveController] Save result:', result)

      if (result.success) {
        console.log('[PlaygroundSaveController] Save successful!')
        this.showAlert(result.message || 'Saved successfully!', 'success')

        // Redirect if URL provided
        if (result.redirect_url) {
          console.log('[PlaygroundSaveController] Redirecting to:', result.redirect_url)
          setTimeout(() => {
            window.location.href = result.redirect_url
          }, 1000)
        }
      } else {
        console.error('[PlaygroundSaveController] Save failed:', result.errors)
        this.showAlert(result.errors?.join(', ') || 'Save failed', 'danger')
      }

      this.showSaveLoading(saveAction, false)
    } catch (error) {
      console.error('[PlaygroundSaveController] Network error:', error)
      this.showAlert(`Network error: ${error.message}`, 'danger')
      this.showSaveLoading(saveAction, false)
    }

    console.log('[PlaygroundSaveController] ========== SAVE COMPLETE ==========')
  }

  // Action: Prompt name input
  onPromptNameInput() {
    console.log('[PlaygroundSaveController] onPromptNameInput() called')

    if (!this.hasPromptNameTarget || !this.hasPromptSlugTarget) return

    const name = this.promptNameTarget.value.trim()

    // Auto-generate slug if it's empty or matches the previous auto-generated slug
    if (!this.promptSlugTarget.value || this.promptSlugTarget.dataset.autoGenerated === 'true') {
      const slug = this.generateSlugFromName(name)
      this.promptSlugTarget.value = slug
      this.promptSlugTarget.dataset.autoGenerated = 'true'
      console.log('[PlaygroundSaveController] Auto-generated slug:', slug)
    }
  }

  // Action: Prompt slug input (manual edit)
  onPromptSlugInput() {
    console.log('[PlaygroundSaveController] onPromptSlugInput() called')

    if (!this.hasPromptSlugTarget) return

    // Mark as manually edited
    this.promptSlugTarget.dataset.autoGenerated = 'false'
    console.log('[PlaygroundSaveController] Slug manually edited')
  }

  // Generate slug from name
  generateSlugFromName(name) {
    return name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
  }

  // Show save loading state
  showSaveLoading(saveAction, isLoading) {
    console.log('[PlaygroundSaveController] Loading state for', saveAction, ':', isLoading)

    const btnMap = {
      'draft': this.hasSaveDraftBtnTarget ? this.saveDraftBtnTarget : null,
      'update': this.hasSaveUpdateBtnTarget ? this.saveUpdateBtnTarget : null,
      'new_version': this.hasSaveNewVersionBtnTarget ? this.saveNewVersionBtnTarget : null
    }

    const btn = btnMap[saveAction]
    if (btn) {
      btn.disabled = isLoading

      if (isLoading) {
        btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Saving...'
      } else {
        // Reset button text
        if (saveAction === 'draft') {
          btn.innerHTML = '<i class="bi bi-save"></i> Save Draft'
        } else if (saveAction === 'update') {
          btn.innerHTML = '<i class="bi bi-save"></i> Update'
        } else if (saveAction === 'new_version') {
          btn.innerHTML = '<i class="bi bi-plus-circle"></i> Save as New Version'
        }
      }
    }

    if (this.hasSaveStatusTarget) {
      if (isLoading) {
        this.saveStatusTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Saving...'
        this.saveStatusTarget.style.display = ''
      } else {
        this.saveStatusTarget.style.display = 'none'
      }
    }
  }

  // Show alert
  showAlert(message, type = 'info') {
    console.log('[PlaygroundSaveController] Showing alert:', type, message)

    if (!this.hasAlertContainerTarget) {
      console.warn('[PlaygroundSaveController] No alert container target')
      return
    }

    const alertHtml = `
      <div class="alert alert-${type} alert-dismissible fade show" role="alert">
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
      </div>
    `

    this.alertContainerTarget.innerHTML = alertHtml

    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      const alert = this.alertContainerTarget.querySelector('.alert')
      if (alert) {
        alert.classList.remove('show')
        setTimeout(() => {
          this.alertContainerTarget.innerHTML = ''
        }, 150)
      }
    }, 5000)
  }

  // Get CSRF token
  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
