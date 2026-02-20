import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

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
    "saveBtn",
    "saveDraftBtn",
    "saveUpdateBtn",
    "saveNewVersionBtn",
    "alertContainer",
    "saveStatus"
    // Note: Modal elements are accessed via document.getElementById() because
    // Bootstrap moves modals to <body>, taking them outside the Stimulus controller scope
  ]

  static values = {
    saveUrl: String,
    checkVersionImpactUrl: String,
    promptId: String,
    promptName: String,
    versionId: String,
    currentVersionNumber: Number
  }

  static outlets = [
    "playground-prompt-editor",
    "playground-variables",
    "playground-model-config",
    "playground-response-schema",
    "playground-tools",
    "playground-file-search",
    "playground-functions"
  ]

  connect() {
    console.log('[PlaygroundSaveController] ========== CONNECT ==========')
    console.log('[PlaygroundSaveController] Element:', this.element)
    console.log('[PlaygroundSaveController] Prompt ID:', this.promptIdValue)
    console.log('[PlaygroundSaveController] Version ID:', this.versionIdValue)
    console.log('[PlaygroundSaveController] Save URL:', this.saveUrlValue)
    console.log('[PlaygroundSaveController] Has prompt editor outlet?', this.hasPlaygroundPromptEditorOutlet)
    console.log('[PlaygroundSaveController] Has variables outlet?', this.hasPlaygroundVariablesOutlet)
    console.log('[PlaygroundSaveController] Has model-config outlet?', this.hasPlaygroundModelConfigOutlet)
    console.log('[PlaygroundSaveController] Has tools outlet?', this.hasPlaygroundToolsOutlet)
    console.log('[PlaygroundSaveController] Has file-search outlet?', this.hasPlaygroundFileSearchOutlet)
    console.log('[PlaygroundSaveController] Has functions outlet?', this.hasPlaygroundFunctionsOutlet)

    // Listen for modal button clicks (modal is outside controller scope due to Bootstrap)
    this.handleConfirmUpdate = this.handleConfirmUpdate.bind(this)
    this.handleConfirmNewVersion = this.handleConfirmNewVersion.bind(this)
    this.element.addEventListener('save-modal:confirm-update', this.handleConfirmUpdate)
    this.element.addEventListener('save-modal:confirm-new-version', this.handleConfirmNewVersion)

    console.log('[PlaygroundSaveController] ========== CONNECT COMPLETE ==========')
  }

  disconnect() {
    // Clean up event listeners
    this.element.removeEventListener('save-modal:confirm-update', this.handleConfirmUpdate)
    this.element.removeEventListener('save-modal:confirm-new-version', this.handleConfirmNewVersion)
  }

  // Handle confirm update event from modal
  handleConfirmUpdate() {
    console.log('[PlaygroundSaveController] ========== CONFIRM UPDATE (via event) ==========')
    this.hideSaveModal()
    this.performSave('update')
  }

  // Handle confirm new version event from modal
  handleConfirmNewVersion() {
    console.log('[PlaygroundSaveController] ========== CONFIRM NEW VERSION (via event) ==========')
    this.hideSaveModal()
    this.performSave('new_version')
  }

  // Action: Smart save - checks version impact first
  async save(event) {
    console.log('[PlaygroundSaveController] ========== SAVE ==========')
    event.preventDefault()

    // First validate inputs before checking version impact
    if (!this.validateBeforeSave()) return

    // Check version impact
    const impact = await this.checkVersionImpact()
    if (!impact) return // Error already shown

    console.log('[PlaygroundSaveController] Version impact:', impact)

    if (impact.will_create_new_version) {
      // Forced to create new version - show confirmation modal
      this.showForcedNewVersionModal(impact)
    } else if (impact.structural_change && impact.reason === 'structural_change_development') {
      // Structural change in Development state - show info modal
      this.showStructuralChangeInfoModal(impact)
    } else {
      // Both options available - show choice modal
      this.showChoiceModal(impact)
    }
  }

  // Action: Save draft (standalone mode)
  async saveDraft(event) {
    console.log('[PlaygroundSaveController] ========== SAVE DRAFT ==========')
    event.preventDefault()
    await this.performSave('draft')
  }

  // Action: Confirm update from modal
  async confirmUpdate(event) {
    console.log('[PlaygroundSaveController] ========== CONFIRM UPDATE ==========')
    event.preventDefault()
    this.hideSaveModal()
    await this.performSave('update')
  }

  // Action: Confirm new version from modal
  async confirmNewVersion(event) {
    console.log('[PlaygroundSaveController] ========== CONFIRM NEW VERSION ==========')
    event.preventDefault()
    this.hideSaveModal()
    await this.performSave('new_version')
  }

  // Check version impact via API
  async checkVersionImpact() {
    const url = this.checkVersionImpactUrlValue
    if (!url) {
      console.warn('[PlaygroundSaveController] No check version impact URL configured')
      // Fallback to direct save
      return { will_create_new_version: false, reason: null }
    }

    // Collect current data to send for comparison
    const data = this.collectSaveData()
    if (!data) return null

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          model_config: data.model_config,
          user_prompt: data.user_prompt,
          response_schema: data.response_schema
        })
      })

      if (!response.ok) {
        console.error('[PlaygroundSaveController] Check version impact failed:', response.status)
        this.showAlert('Failed to check version impact', 'danger')
        return null
      }

      return await response.json()
    } catch (error) {
      console.error('[PlaygroundSaveController] Check version impact error:', error)
      this.showAlert(`Error: ${error.message}`, 'danger')
      return null
    }
  }

  // Get modal elements by ID (Bootstrap moves modals to <body>, outside Stimulus scope)
  getSaveModalElements() {
    return {
      modal: document.getElementById('saveModal'),
      header: document.getElementById('saveModalHeader'),
      title: document.getElementById('saveModalTitle'),
      message: document.getElementById('saveModalMessage'),
      info: document.getElementById('saveModalInfo'),
      updateBtn: document.getElementById('saveModalUpdateBtn'),
      newVersionBtn: document.getElementById('saveModalNewVersionBtn'),
      newVersionBtnText: document.getElementById('saveModalNewVersionBtnText'),
      newVersionNumber: document.getElementById('saveModalNewVersionNumber')
    }
  }

  // Show modal for forced new version (production/structural change)
  showForcedNewVersionModal(impact) {
    const elements = this.getSaveModalElements()

    if (!elements.modal) {
      console.warn('[PlaygroundSaveController] No save modal found')
      // Fallback to confirm dialog
      if (confirm(`${impact.message}\n\nDo you want to create a new version?`)) {
        this.performSave('new_version')
      }
      return
    }

    // Configure modal for forced new version
    if (elements.header) elements.header.className = 'modal-header bg-warning'
    if (elements.title) elements.title.innerHTML = '<i class="bi bi-exclamation-triangle me-2"></i>New Version Required'
    if (elements.message) elements.message.textContent = impact.message

    // Show info box
    if (elements.info) elements.info.style.display = ''

    // Update version number
    if (elements.newVersionNumber) {
      const nextVersion = (this.currentVersionNumberValue || 1) + 1
      elements.newVersionNumber.textContent = nextVersion
    }

    // Hide update button, show only new version
    if (elements.updateBtn) elements.updateBtn.style.display = 'none'
    if (elements.newVersionBtn) elements.newVersionBtn.className = 'btn btn-primary'
    if (elements.newVersionBtnText) elements.newVersionBtnText.textContent = 'Create New Version'

    this.showSaveModal()
  }

  // Show info modal for structural changes in Development state
  showStructuralChangeInfoModal(impact) {
    const elements = this.getSaveModalElements()

    if (!elements.modal) {
      console.warn('[PlaygroundSaveController] No save modal found')
      // Fallback to confirm dialog
      if (confirm(`${impact.message}\n\nDo you want to continue?`)) {
        this.performSave('update')
      }
      return
    }

    // Configure modal for structural change info (Development state)
    if (elements.header) elements.header.className = 'modal-header bg-info text-white'
    if (elements.title) elements.title.innerHTML = '<i class="bi bi-info-circle me-2"></i>Structural Change Detected'
    if (elements.message) elements.message.textContent = impact.message

    // Hide info box (the message already explains it)
    if (elements.info) elements.info.style.display = 'none'

    // Show only update button (since we're in Development state, update is allowed)
    if (elements.updateBtn) {
      elements.updateBtn.style.display = ''
      elements.updateBtn.className = 'btn btn-primary'
    }
    // Also show new version as secondary option
    if (elements.newVersionBtn) elements.newVersionBtn.className = 'btn btn-outline-secondary'
    if (elements.newVersionBtnText) elements.newVersionBtnText.textContent = 'Save as New Version'

    this.showSaveModal()
  }

  // Show modal with both options (update or new version)
  // eslint-disable-next-line no-unused-vars
  showChoiceModal(_impact) {
    const elements = this.getSaveModalElements()

    if (!elements.modal) {
      console.warn('[PlaygroundSaveController] No save modal found')
      // Fallback to direct update
      this.performSave('update')
      return
    }

    // Configure modal for choice
    if (elements.header) elements.header.className = 'modal-header'
    if (elements.title) elements.title.innerHTML = '<i class="bi bi-save me-2"></i>Save Changes'
    if (elements.message) elements.message.textContent = 'How would you like to save your changes?'

    // Hide info box
    if (elements.info) elements.info.style.display = 'none'

    // Show both buttons with standard styling
    if (elements.updateBtn) {
      elements.updateBtn.style.display = ''
      elements.updateBtn.className = 'btn btn-primary'
    }
    if (elements.newVersionBtn) elements.newVersionBtn.className = 'btn btn-outline-secondary'
    if (elements.newVersionBtnText) elements.newVersionBtnText.textContent = 'Save as New Version'

    this.showSaveModal()
  }

  showSaveModal() {
    const modalEl = document.getElementById('saveModal')
    if (!modalEl) return
    const modal = new Modal(modalEl)
    modal.show()
  }

  hideSaveModal() {
    const modalEl = document.getElementById('saveModal')
    if (!modalEl) return
    const modal = Modal.getInstance(modalEl)
    if (modal) modal.hide()
  }

  // Validate inputs before save
  validateBeforeSave() {
    // Validate required outlets
    if (!this.hasPlaygroundPromptEditorOutlet) {
      console.error('[PlaygroundSaveController] Missing prompt editor outlet')
      this.showAlert('Missing prompt editor controller', 'danger')
      return false
    }

    if (!this.hasPlaygroundModelConfigOutlet) {
      console.error('[PlaygroundSaveController] Missing model-config outlet')
      this.showAlert('Missing model-config controller', 'danger')
      return false
    }

    // Get prompt name
    const promptName = this.hasPromptNameTarget
      ? this.promptNameTarget.value.trim()
      : (this.promptNameValue || '')

    if (!promptName) {
      console.error('[PlaygroundSaveController] Prompt name is required')
      this.showAlert('Prompt name is required', 'warning')
      return false
    }

    return true
  }

  // Collect save data (shared between checkVersionImpact and performSave)
  collectSaveData() {
    if (!this.validateBeforeSave()) return null

    const promptName = this.hasPromptNameTarget
      ? this.promptNameTarget.value.trim()
      : (this.promptNameValue || '')

    // Get base model config
    const modelConfig = this.playgroundModelConfigOutlet.getModelConfig()

    // Add tools data from tools controllers
    if (this.hasPlaygroundToolsOutlet) {
      const selectedTools = this.playgroundToolsOutlet.getSelectedTools()
      if (selectedTools.length > 0) {
        modelConfig.tools = selectedTools
      }
    }

    // Build tool_config from file-search and functions controllers
    const toolConfig = {}

    if (modelConfig.tools?.includes('file_search') && this.hasPlaygroundFileSearchOutlet) {
      toolConfig.file_search = this.playgroundFileSearchOutlet.getVectorStoreConfig()
    }

    if (modelConfig.tools?.includes('functions') && this.hasPlaygroundFunctionsOutlet) {
      const functionsConfig = this.playgroundFunctionsOutlet.getFunctionsConfig()
      if (functionsConfig.length > 0) {
        toolConfig.functions = functionsConfig
      }
    }

    if (Object.keys(toolConfig).length > 0) {
      modelConfig.tool_config = toolConfig
    }

    return {
      prompt_name: promptName,
      prompt_slug: this.hasPromptSlugTarget ? this.promptSlugTarget.value : '',
      system_prompt: this.playgroundPromptEditorOutlet.getSystemPrompt(),
      user_prompt: this.playgroundPromptEditorOutlet.getUserPrompt(),
      template_variables: this.hasPlaygroundVariablesOutlet
        ? this.playgroundVariablesOutlet.getVariables()
        : {},
      model_config: modelConfig
    }
  }

  // Perform save operation
  // @param saveAction [String] - 'draft', 'update', or 'new_version'
  async performSave(saveAction) {
    console.log('[PlaygroundSaveController] performSave() called with action:', saveAction)

    // Collect data using shared method
    const data = this.collectSaveData()
    if (!data) return

    // Add save action
    data.save_action = saveAction

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
  // Slug must use underscores (not hyphens) to match model validation
  generateSlugFromName(name) {
    return name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '')
  }

  // Show save loading state
  showSaveLoading(saveAction, isLoading) {
    console.log('[PlaygroundSaveController] Loading state for', saveAction, ':', isLoading)

    // Handle the main save button (new UI)
    if (this.hasSaveBtnTarget) {
      this.saveBtnTarget.disabled = isLoading
      if (isLoading) {
        this.saveBtnTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Saving...'
      } else {
        this.saveBtnTarget.innerHTML = '<i class="bi bi-save"></i> Save'
      }
    }

    // Handle legacy button targets (for standalone mode and backwards compatibility)
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
