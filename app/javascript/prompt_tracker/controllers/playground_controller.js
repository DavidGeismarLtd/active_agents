import { Controller } from "@hotwired/stimulus"
import { Modal, Collapse } from "bootstrap"

/**
 * PromptPlayground Stimulus Controller
 * Interactive prompt template editor with live preview
 */
export default class extends Controller {
  static targets = [
    "systemPromptEditor",
    "userPromptEditor",
    "templateEditor", // Keep for backward compatibility during migration
    "variablesContainer",
    "previewContainer",
    "previewError",
    "engineBadge",
    "refreshBtn",
    "saveDraftBtn",
    "saveUpdateBtn",
    "saveNewVersionBtn",
    "alertContainer",
    "alertMessage",
    "promptNameInput",
    "charCount",
    "previewStatus",
    "modelProvider",
    "modelName",
    "modelTemperature",
    "modelMaxTokens",
    "modelTopP",
    "modelFrequencyPenalty",
    "modelPresencePenalty",
    "temperatureBadge",
    "aiButton",
    "aiButtonText",
    "aiButtonIcon"
  ]

  static values = {
    promptId: Number,
    versionId: Number,
    versionHasResponses: Boolean,
    previewUrl: String,
    saveUrl: String,
    generateUrl: String,
    isStandalone: Boolean
  }

  connect() {
    this.debounceTimer = null
    this.debounceDelay = 500 // ms

    this.attachEventListeners()
    this.attachModalEventListeners() // Attach listeners for modals that get moved by modal-fix
    this.updatePreview() // Initial preview
    this.updateAIButtonState() // Update button text based on content
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  attachEventListeners() {
    // Tab key in user prompt editor (insert 2 spaces)
    if (this.hasUserPromptEditorTarget) {
      this.userPromptEditorTarget.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault()
          const start = this.userPromptEditorTarget.selectionStart
          const end = this.userPromptEditorTarget.selectionEnd
          const value = this.userPromptEditorTarget.value
          this.userPromptEditorTarget.value = value.substring(0, start) + '  ' + value.substring(end)
          this.userPromptEditorTarget.selectionStart = this.userPromptEditorTarget.selectionEnd = start + 2
          this.userPromptEditorTarget.dispatchEvent(new Event('input'))
        }
      })
    }

    // Tab key in system prompt editor (insert 2 spaces)
    if (this.hasSystemPromptEditorTarget) {
      this.systemPromptEditorTarget.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault()
          const start = this.systemPromptEditorTarget.selectionStart
          const end = this.systemPromptEditorTarget.selectionEnd
          const value = this.systemPromptEditorTarget.value
          this.systemPromptEditorTarget.value = value.substring(0, start) + '  ' + value.substring(end)
          this.systemPromptEditorTarget.selectionStart = this.systemPromptEditorTarget.selectionEnd = start + 2
          this.systemPromptEditorTarget.dispatchEvent(new Event('input'))
        }
      })
    }

    // Example template buttons
    document.querySelectorAll('.use-example-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const template = btn.dataset.template
        if (this.hasUserPromptEditorTarget) {
          this.userPromptEditorTarget.value = template
          this.userPromptEditorTarget.dispatchEvent(new Event('input'))
        }
        // Close modal
        const modal = Modal.getInstance(document.getElementById('templateExamplesModal'))
        if (modal) modal.hide()
        this.showAlert('Template loaded! Customize it as needed.', 'success')
      })
    })

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      this.handleKeyboardShortcuts(e)
    })

    // Initial character count
    this.updateCharCount()
  }

  /**
   * Attach event listeners for modal buttons
   * These modals get moved to document.body by modal-fix controller,
   * so we can't use data-action attributes (they lose controller scope)
   */
  attachModalEventListeners() {
    // Generate Prompt button in modal
    const generateButton = document.getElementById('generatePromptButton')
    if (generateButton) {
      generateButton.addEventListener('click', () => {
        this.submitGeneration()
      })
    }
  }

  // Action: User prompt editor input
  onUserPromptInput() {
    this.debouncedUpdatePreview()
    this.updateVariableInputs()
    this.updateCharCount()
    this.updateAIButtonState()
  }

  // Action: System prompt editor input
  onSystemPromptInput() {
    this.debouncedUpdatePreview()
    this.updateVariableInputs()
    this.updateCharCount()
    this.updateAIButtonState()
  }

  // Backward compatibility
  onTemplateInput() {
    this.onUserPromptInput()
  }

  // Action: Variable input
  onVariableInput(event) {
    if (event.target.classList.contains('variable-input')) {
      this.debouncedUpdatePreview()
    }
  }

  // Action: Model config change
  onModelConfigChange() {
    // Update temperature badge
    if (this.hasTemperatureBadgeTarget && this.hasModelTemperatureTarget) {
      this.temperatureBadgeTarget.textContent = this.modelTemperatureTarget.value
    }
  }

  // Action: Refresh preview
  refreshPreview() {
    this.updatePreview()
  }

  // Action: Save draft
  saveDraft(event) {
    const saveAction = event?.params?.action || 'new_version'
    this.performSave(saveAction)
  }

  debouncedUpdatePreview() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => {
      this.updatePreview()
    }, this.debounceDelay)
  }

  async updatePreview() {
    const systemPrompt = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value : ''
    const userPrompt = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value : ''
    const variables = this.collectVariables()

    if (!userPrompt.trim()) {
      this.previewContainerTarget.innerHTML = '<p class="text-muted">Enter a user prompt to see preview...</p>'
      this.previewErrorTarget.style.display = 'none'
      return
    }

    // Check for incomplete Liquid/Mustache syntax
    if (this.hasIncompleteSyntax(userPrompt) || this.hasIncompleteSyntax(systemPrompt)) {
      this.previewContainerTarget.innerHTML = '<p class="text-muted"><i class="bi bi-pencil"></i> Typing...</p>'
      this.previewErrorTarget.style.display = 'none'
      return
    }

    // Show loading state
    this.showPreviewLoading(true)

    try {
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

      if (!response.ok) {
        const text = await response.text()
        console.error('Server error response:', text)
        this.showPreviewError([`Server error (${response.status}): ${response.statusText}`])
        this.showPreviewLoading(false)
        return
      }

      const contentType = response.headers.get('content-type')
      if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text()
        console.error('Non-JSON response:', text)
        this.showPreviewError(['Server returned non-JSON response. Check console for details.'])
        this.showPreviewLoading(false)
        return
      }

      const data = await response.json()

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
        this.updateVariablesFromDetection(data.variables_detected)
      } else {
        this.showPreviewError(data.errors)
      }
    } catch (error) {
      console.error('Preview error:', error)
      this.showPreviewError(['Network error: ' + error.message])
    } finally {
      this.showPreviewLoading(false)
    }
  }

  updateVariableInputs() {
    const userPrompt = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value : ''
    const systemPrompt = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value : ''

    // Extract variables from both prompts
    const userVariables = this.extractVariables(userPrompt)
    const systemVariables = this.extractVariables(systemPrompt)

    // Combine and deduplicate variables
    const allVariables = [...new Set([...systemVariables, ...userVariables])]

    // Get current variable values
    const currentValues = this.collectVariables()

    // Rebuild variable inputs
    if (allVariables.length === 0) {
      this.variablesContainerTarget.innerHTML = '<p class="text-muted">No variables detected. Start typing in the prompt editors.</p>'
      return
    }

    let html = ''
    allVariables.forEach(varName => {
      const value = currentValues[varName] || ''
      html += `
        <div class="mb-2">
          <label for="var-${varName}" class="form-label"><code>${varName}</code></label>
          <input
            type="text"
            class="form-control variable-input"
            id="var-${varName}"
            data-variable-name="${varName}"
            value="${this.escapeHtml(value)}"
            placeholder="Enter value for ${varName}"
            data-action="input->playground#onVariableInput"
          >
        </div>
      `
    })

    this.variablesContainerTarget.innerHTML = html
  }

  updateVariablesFromDetection(detectedVars) {
    // This is called after preview to ensure we have all variables
    // Only update if we have new variables
    if (!detectedVars || detectedVars.length === 0) return

    const currentVars = Array.from(this.variablesContainerTarget.querySelectorAll('.variable-input'))
      .map(input => input.dataset.variableName)

    const newVars = detectedVars.filter(v => !currentVars.includes(v))

    if (newVars.length > 0) {
      this.updateVariableInputs()
    }
  }

  extractVariables(template) {
    const variables = new Set()

    // Liquid-style: {{ variable }}
    const simpleMatches = template.matchAll(/\{\{\s*(\w+)\s*\}\}/g)
    for (const match of simpleMatches) {
      variables.add(match[1])
    }

    // Liquid filters: {{ variable | filter }}
    const filterMatches = template.matchAll(/\{\{\s*(\w+)\s*\|/g)
    for (const match of filterMatches) {
      variables.add(match[1])
    }

    // Liquid object notation: {{ object.property }}
    const objectMatches = template.matchAll(/\{\{\s*(\w+)\./g)
    for (const match of objectMatches) {
      variables.add(match[1])
    }

    return Array.from(variables).sort()
  }

  hasIncompleteSyntax(template) {
    // Check for incomplete {{ or {% tags
    const openBraces = (template.match(/\{\{/g) || []).length
    const closeBraces = (template.match(/\}\}/g) || []).length
    const openTags = (template.match(/\{%/g) || []).length
    const closeTags = (template.match(/%\}/g) || []).length

    return openBraces !== closeBraces || openTags !== closeTags
  }

  collectVariables() {
    const variables = {}
    const inputs = this.variablesContainerTarget.querySelectorAll('.variable-input')

    inputs.forEach(input => {
      const name = input.dataset.variableName
      const value = input.value
      if (name) {
        variables[name] = value
      }
    })

    return variables
  }

  updateEngineBadge() {
    this.engineBadgeTarget.textContent = 'Liquid'
    this.engineBadgeTarget.className = 'badge bg-primary'
  }

  showPreviewError(errors) {
    this.previewErrorTarget.innerHTML = '<strong>Preview Error:</strong><br>' + errors.join('<br>')
    this.previewErrorTarget.style.display = 'block'
    this.previewContainerTarget.innerHTML = '<p class="text-muted">Fix errors to see preview...</p>'
  }

  async performSave(saveAction = 'new_version') {
    const userPrompt = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value : ''
    const systemPrompt = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value : ''

    if (!userPrompt.trim()) {
      this.showAlert('Please enter a user prompt before saving.', 'warning')
      return
    }

    // Validate prompt name in standalone mode
    let promptName = null
    if (this.isStandaloneValue) {
      if (!this.hasPromptNameInputTarget || !this.promptNameInputTarget.value.trim()) {
        this.showAlert('Please enter a prompt name.', 'warning')
        if (this.hasPromptNameInputTarget) {
          this.promptNameInputTarget.focus()
        }
        return
      }
      promptName = this.promptNameInputTarget.value.trim()
    }

    const notes = prompt('Add notes for this version (optional):')
    if (notes === null) return // User cancelled

    // Disable all save buttons and show loading state
    const activeButton = saveAction === 'update' ? this.saveUpdateBtnTarget :
                        (this.hasSaveNewVersionBtnTarget ? this.saveNewVersionBtnTarget : this.saveDraftBtnTarget)

    if (activeButton) {
      activeButton.disabled = true
      activeButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Saving...'
    }

    const requestBody = {
      user_prompt: userPrompt,
      system_prompt: systemPrompt,
      notes: notes,
      save_action: saveAction,
      model_config: this.getModelConfig()
    }

    if (this.isStandaloneValue) {
      requestBody.prompt_name = promptName
    }

    try {
      const response = await fetch(this.saveUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken()
        },
        body: JSON.stringify(requestBody)
      })

      const data = await response.json()

      if (data.success) {
        if (this.isStandaloneValue) {
          this.showAlert(`Prompt "${promptName}" created successfully!`, 'success')
        } else if (data.action === 'updated') {
          this.showAlert(`Version ${data.version_number} updated successfully!`, 'success')
        } else {
          this.showAlert(`Draft version ${data.version_number} created successfully!`, 'success')
        }
        setTimeout(() => {
          window.location.href = data.redirect_url
        }, 1500)
      } else {
        this.showAlert('Error: ' + data.errors.join(', '), 'danger')
        this.resetSaveButtons(saveAction)
      }
    } catch (error) {
      this.showAlert('Network error: ' + error.message, 'danger')
      this.resetSaveButtons(saveAction)
    }
  }

  resetSaveButtons(saveAction) {
    if (this.isStandaloneValue && this.hasSaveDraftBtnTarget) {
      this.saveDraftBtnTarget.disabled = false
      this.saveDraftBtnTarget.innerHTML = '<i class="bi bi-save"></i> Create Prompt'
    } else if (saveAction === 'update' && this.hasSaveUpdateBtnTarget) {
      this.saveUpdateBtnTarget.disabled = false
      this.saveUpdateBtnTarget.innerHTML = '<i class="bi bi-save"></i> Update This Version'
    } else if (this.hasSaveNewVersionBtnTarget) {
      this.saveNewVersionBtnTarget.disabled = false
      this.saveNewVersionBtnTarget.innerHTML = '<i class="bi bi-plus-circle"></i> Save as New Version'
    } else if (this.hasSaveDraftBtnTarget) {
      this.saveDraftBtnTarget.disabled = false
      this.saveDraftBtnTarget.innerHTML = '<i class="bi bi-save"></i> Save as Draft Version'
    }
  }

  showAlert(message, type) {
    this.alertMessageTarget.textContent = message
    this.alertContainerTarget.className = `alert alert-${type} alert-dismissible fade show`
    this.alertContainerTarget.style.display = 'block'

    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      this.alertContainerTarget.classList.remove('show')
    }, 5000)
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  updateCharCount() {
    const userPromptLength = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value.length : 0
    const systemPromptLength = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value.length : 0
    const count = userPromptLength + systemPromptLength

    this.charCountTarget.textContent = `${count} chars`

    // Color code based on length
    if (count > 2000) {
      this.charCountTarget.className = 'badge bg-danger'
    } else if (count > 1000) {
      this.charCountTarget.className = 'badge bg-warning'
    } else {
      this.charCountTarget.className = 'badge bg-info'
    }
  }

  showPreviewLoading(isLoading) {
    if (this.hasPreviewStatusTarget) {
      this.previewStatusTarget.style.display = isLoading ? 'inline-block' : 'none'
    }
  }

  // ========================================
  // ENHANCE PROMPT METHODS
  // ========================================

  /**
   * Main action: Enhance or generate prompts using AI
   */
  async enhancePrompt() {
    const systemPrompt = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value : ''
    const userPrompt = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value : ''
    const context = this.hasPromptNameInputTarget ? this.promptNameInputTarget.value : ''

    // Show loading state
    this.showEnhanceLoading(true)

    try {
      const response = await fetch(this.enhanceUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          system_prompt: systemPrompt,
          user_prompt: userPrompt,
          context: context
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || `Server error (${response.status})`)
      }

      const data = await response.json()

      if (data.success) {
        // Animate the enhanced prompts into the editors
        if (data.system_prompt && this.hasSystemPromptEditorTarget) {
          await this.animateTextInsertion(this.systemPromptEditorTarget, data.system_prompt)
        }

        if (data.user_prompt && this.hasUserPromptEditorTarget) {
          await this.animateTextInsertion(this.userPromptEditorTarget, data.user_prompt)
        }

        // Update variables and preview
        this.updateVariableInputs()
        this.updatePreview()

        // Show success message with explanation
        const message = data.explanation || 'Prompt enhanced successfully!'
        this.showAlert(message, 'success')
      } else {
        throw new Error(data.error || 'Enhancement failed')
      }
    } catch (error) {
      console.error('Enhancement error:', error)
      this.showAlert(`Enhancement failed: ${error.message}`, 'danger')
    } finally {
      this.showEnhanceLoading(false)
    }
  }

  /**
   * Animate text insertion with typewriter effect
   */
  async animateTextInsertion(textarea, newText, speed = 2) {
    // Clear existing content
    textarea.value = ''

    // Animate character by character
    for (let i = 0; i < newText.length; i++) {
      textarea.value += newText[i]

      // Trigger input event periodically for live updates
      if (i % 50 === 0 || i === newText.length - 1) {
        textarea.dispatchEvent(new Event('input'))
      }

      // Delay between characters (skip for whitespace to speed up)
      const char = newText[i]
      const delay = (char === ' ' || char === '\n') ? speed / 3 : speed
      await new Promise(resolve => setTimeout(resolve, delay))
    }

    // Final input event to ensure everything is updated
    textarea.dispatchEvent(new Event('input'))
  }

  /**
   * Show/hide enhancement loading overlay
   */
  showEnhanceLoading(isLoading) {
    // Update button state
    if (this.hasEnhanceBtnTarget) {
      this.enhanceBtnTarget.disabled = isLoading
      this.enhanceBtnTarget.innerHTML = isLoading ?
        '<span class="spinner-border spinner-border-sm me-1"></span>Enhancing...' :
        '<i class="bi bi-magic"></i> Enhance'
    }

    // Show/hide overlay
    if (this.hasEnhanceOverlayTarget) {
      this.enhanceOverlayTarget.style.display = isLoading ? 'flex' : 'none'
    }
  }

  // ========================================
  // AI BUTTON - GENERATE ONLY
  // ========================================

  /**
   * Check if prompts are empty
   */
  get isPromptsEmpty() {
    const systemPrompt = this.hasSystemPromptEditorTarget ? this.systemPromptEditorTarget.value.trim() : ''
    const userPrompt = this.hasUserPromptEditorTarget ? this.userPromptEditorTarget.value.trim() : ''
    return systemPrompt === '' && userPrompt === ''
  }

  /**
   * Update AI button visibility based on content state
   * Only show when prompts are empty (generate mode)
   */
  updateAIButtonState() {
    if (!this.hasAiButtonTarget) return

    if (this.isPromptsEmpty) {
      this.aiButtonTarget.style.display = ''
      if (this.hasAiButtonTextTarget) {
        this.aiButtonTextTarget.textContent = 'Generate'
      }
      if (this.hasAiButtonIconTarget) {
        this.aiButtonIconTarget.className = 'bi bi-stars'
      }
    } else {
      // Hide button when prompts have content
      this.aiButtonTarget.style.display = 'none'
    }
  }

  /**
   * Handle AI button click - opens generate modal
   */
  handleAIButtonClick() {
    this.openGenerateModal()
  }

  // ========================================
  // GENERATE FEATURE
  // ========================================

  /**
   * Open the generate prompt modal
   */
  openGenerateModal() {
    const modalEl = document.getElementById('generatePromptModal')
    if (modalEl) {
      const modal = new Modal(modalEl)
      modal.show()
    }
  }

  /**
   * Submit generation request
   */
  async submitGeneration() {
    // Use getElementById since modal gets moved to document.body by modal-fix
    const descriptionTextarea = document.getElementById('generateDescription')

    if (!descriptionTextarea) {
      return
    }

    const description = descriptionTextarea.value.trim()

    if (!description) {
      this.showAlert('Please describe what your prompt should do', 'warning')
      return
    }

    // Close the input modal
    const inputModalEl = document.getElementById('generatePromptModal')
    if (inputModalEl) {
      const inputModal = Modal.getInstance(inputModalEl)
      if (inputModal) inputModal.hide()
    }

    // Show generating modal
    this.showGeneratingModal()

    try {
      await this.generatePromptFromDescription(description)
    } catch (error) {
      console.error('Generation error:', error)
    } finally {
      this.hideGeneratingModal()
      // Clear the description for next time
      if (descriptionTextarea) {
        descriptionTextarea.value = ''
      }
    }
  }

  /**
   * Generate prompt from description with animation
   */
  async generatePromptFromDescription(description) {
    try {
      const response = await fetch(this.generateUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ description })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || `Server error (${response.status})`)
      }

      const data = await response.json()

      if (data.success) {
        // Animate the generated prompts
        if (data.system_prompt && this.hasSystemPromptEditorTarget) {
          await this.animateTextInsertion(this.systemPromptEditorTarget, data.system_prompt)
        }

        if (data.user_prompt && this.hasUserPromptEditorTarget) {
          await this.animateTextInsertion(this.userPromptEditorTarget, data.user_prompt)
        }

        // Update variables and preview
        this.updateVariableInputs()
        this.updatePreview()
        this.updateAIButtonState()

        // Show success message with explanation
        const message = data.explanation || 'Prompt generated successfully!'
        this.showAlert(message, 'success')
      } else {
        throw new Error(data.error || 'Generation failed')
      }
    } catch (error) {
      console.error('Generation error:', error)
      this.showAlert(`Generation failed: ${error.message}`, 'danger')
    }
  }

  /**
   * Show generating modal
   */
  showGeneratingModal() {
    const modalEl = document.getElementById('generatingModal')
    if (modalEl) {
      this.generatingModal = new Modal(modalEl)
      this.generatingModal.show()
    }
  }

  /**
   * Hide generating modal
   */
  hideGeneratingModal() {
    if (this.generatingModal) {
      this.generatingModal.hide()
      this.generatingModal = null
    }
  }

  handleKeyboardShortcuts(e) {
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0
    const modKey = isMac ? e.metaKey : e.ctrlKey

    // Ctrl/Cmd + Enter: Refresh preview
    if (modKey && e.key === 'Enter') {
      e.preventDefault()
      this.updatePreview()
      this.showAlert('Preview refreshed', 'info')
    }

    // Ctrl/Cmd + S: Save draft
    if (modKey && e.key === 's') {
      e.preventDefault()
      this.performSave()
    }

    // Ctrl/Cmd + /: Toggle syntax help
    if (modKey && e.key === '/') {
      e.preventDefault()
      const syntaxHelp = document.getElementById('liquidHelp')
      if (syntaxHelp) {
        const bsCollapse = new Collapse(syntaxHelp, {
          toggle: true
        })
      }
    }
  }

  // Get model configuration from form
  getModelConfig() {
    const config = {}

    if (this.hasModelProviderTarget) {
      config.provider = this.modelProviderTarget.value
    }

    if (this.hasModelNameTarget && this.modelNameTarget.value) {
      config.model = this.modelNameTarget.value
    }

    if (this.hasModelTemperatureTarget) {
      config.temperature = parseFloat(this.modelTemperatureTarget.value)
    }

    if (this.hasModelMaxTokensTarget && this.modelMaxTokensTarget.value) {
      config.max_tokens = parseInt(this.modelMaxTokensTarget.value)
    }

    if (this.hasModelTopPTarget && this.modelTopPTarget.value) {
      config.top_p = parseFloat(this.modelTopPTarget.value)
    }

    if (this.hasModelFrequencyPenaltyTarget && this.modelFrequencyPenaltyTarget.value) {
      config.frequency_penalty = parseFloat(this.modelFrequencyPenaltyTarget.value)
    }

    if (this.hasModelPresencePenaltyTarget && this.modelPresencePenaltyTarget.value) {
      config.presence_penalty = parseFloat(this.modelPresencePenaltyTarget.value)
    }

    return config
  }
}
