import { Controller } from "@hotwired/stimulus"

/**
 * Playground UI Stimulus Controller
 *
 * @description
 * Manages ALL UI visibility in the playground based on provider/API capabilities.
 * This is the ONLY controller responsible for showing/hiding sections and tools.
 *
 * @responsibilities
 * - Show/hide UI panels based on capabilities (system_prompt, user_prompt_template, variables, preview, conversation)
 * - Show/hide tools panel and update tools based on capabilities
 * - Handle provider/API dropdown changes
 * - Update API description text
 * - Update cascading dropdowns (provider → API → models)
 * - Update temperature badge
 *
 * @targets
 * - promptEditorsSection: Container for all prompt editors
 * - systemPromptSection: System prompt editor section
 * - userPromptTemplateSection: User prompt template editor section
 * - promptTemplateSection: Template-specific UI (generate button, badges)
 * - variablesPreviewSection: Variables and preview panels section
 * - conversationSection: Conversation testing panel section
 * - nonTemplateSection: Info message for non-template APIs
 * - modelProvider: Provider dropdown
 * - modelApi: API dropdown
 * - modelName: Model dropdown
 * - apiSelectContainer: Container for API select
 * - apiDescription: API description text
 * - toolsPanelContainer: Tools panel container
 * - toolsPanelContent: Tools panel content area
 * - temperatureBadge: Temperature value badge
 *
 * @values
 * - capabilities (Object): Full capabilities matrix from ApiCapabilities module
 *   Format: { provider: { api: { playground_ui: [...], tools: [...], features: [...] } } }
 *
 * @outlets
 * - playground-conversation: Conversation testing controller
 */
export default class extends Controller {
  static targets = [
    "systemPromptSection",
    "userPromptTemplateSection",
    "variablesPreviewSection",
    "conversationSection",
    "modelProvider",
    "modelApi",
    "modelName",
    "apiSelectContainer",
    "apiDescription",
    "toolsPanelContainer",
    "temperatureBadge"
  ]

  static values = {
    capabilities: Object
  }

  static outlets = ["playground-conversation", "playground-tools"]

  connect() {
    console.log('[PlaygroundUIController] Connected')
    // Initialize UI visibility based on current provider/API
    this.updateVisibility()
  }

  // ========== DROPDOWN CHANGE HANDLERS ==========

  /**
   * Handle provider dropdown change
   * Updates API dropdown options, model dropdown, and triggers visibility update
   */
  onProviderChange(event) {
    const provider = event.target.value
    console.log(`[PlaygroundUIController] Provider changed to: ${provider}`)

    // Update API dropdown options based on provider
    this.updateApiDropdown(provider)

    // Update model dropdown based on new provider/API
    const api = this.hasModelApiTarget ? this.modelApiTarget.value : null
    if (api) {
      this.updateModelDropdown(provider, api)
    }

    // Update visibility
    this.updateVisibility()
  }

  /**
   * Handle API dropdown change
   * Updates model dropdown and triggers visibility update
   */
  onApiChange(event) {
    const api = event.target.value
    console.log(`[PlaygroundUIController] API changed to: ${api}`)

    // Update model dropdown based on new API
    const provider = this.hasModelProviderTarget ? this.modelProviderTarget.value : null
    if (provider) {
      this.updateModelDropdown(provider, api)
    }

    // Update visibility
    this.updateVisibility()
  }

  /**
   * Update visibility of all UI elements based on current provider/API selection
   * This is the main method that orchestrates all visibility updates
   */
  updateVisibility() {
    if (!this.hasModelProviderTarget || !this.hasModelApiTarget) {
      console.warn('[PlaygroundUIController] Provider or API dropdown not found')
      return
    }

    const provider = this.modelProviderTarget.value
    const api = this.modelApiTarget.value

    if (!provider || !api) {
      console.warn('[PlaygroundUIController] Provider or API not selected')
      return
    }

    console.log(`[PlaygroundUIController] Updating visibility for ${provider}/${api}`)

    // Get capabilities for this provider/API combination
    const capabilities = this.getCapabilities(provider, api)
    const playgroundUI = capabilities.playground_ui || []

    console.log(`[PlaygroundUIController] Capabilities:`, capabilities)

    // Update all UI elements
    this.updatePanelVisibility(playgroundUI)
    this.updateConversationVisibility(playgroundUI)
    this.updateToolsVisibility(provider, api)
    this.updateApiDescription(provider, api)
  }

  // ========== HELPER METHODS ==========

  /**
   * Get capabilities for a provider/API combination
   *
   * @param {string} provider - Provider name (e.g., 'openai')
   * @param {string} api - API name (e.g., 'assistants')
   * @returns {Object} Capabilities object with playground_ui, builtin_tools, features arrays
   */
  getCapabilities(provider, api) {
    if (!this.hasCapabilitiesValue) {
      console.warn('[PlaygroundUIController] No capabilities data available')
      return { playground_ui: [], builtin_tools: [], features: [] }
    }

    const capabilities = this.capabilitiesValue
    const providerConfig = capabilities[provider]

    if (!providerConfig) {
      console.warn(`[PlaygroundUIController] Unknown provider: ${provider}`)
      return { playground_ui: [], builtin_tools: [], features: [] }
    }

    const apiConfig = providerConfig[api]

    if (!apiConfig) {
      console.warn(`[PlaygroundUIController] Unknown API: ${api} for provider: ${provider}`)
      return { playground_ui: [], builtin_tools: [], features: [] }
    }

    return apiConfig
  }

  /**
   * Update API dropdown options based on selected provider
   */
  updateApiDropdown(provider) {
    if (!this.hasModelProviderTarget) return

    const providerData = JSON.parse(this.modelProviderTarget.dataset.providerData || '{}')
    const data = providerData[provider]

    if (!data || !data.apis) {
      console.warn(`[PlaygroundUIController] No API data for provider: ${provider}`)
      return
    }

    // Always show API select container (even with single API, for clarity)
    if (this.hasApiSelectContainerTarget) {
      this.apiSelectContainerTarget.style.display = ''
    }

    // Update API dropdown options
    if (this.hasModelApiTarget) {
      this.modelApiTarget.innerHTML = ''

      // Find the default API for this provider, or use the first one
      const defaultApi = data.apis.find(api => api.default) || data.apis[0]

      data.apis.forEach(api => {
        const option = document.createElement('option')
        option.value = api.key
        option.textContent = api.name
        option.dataset.description = api.description
        option.dataset.capabilities = JSON.stringify(api.capabilities)

        // Select the default API for this provider
        if (api.key === defaultApi.key) {
          option.selected = true
        }

        this.modelApiTarget.appendChild(option)
      })
    }
  }

  /**
   * Update model dropdown options based on selected provider and API
   */
  updateModelDropdown(provider, api) {
    if (!this.hasModelProviderTarget || !this.hasModelNameTarget) return

    const providerData = JSON.parse(this.modelProviderTarget.dataset.providerData || '{}')
    const data = providerData[provider]

    if (!data || !data.models_by_api) {
      console.warn(`[PlaygroundUIController] No models_by_api data for provider: ${provider}`)
      return
    }

    const models = data.models_by_api[api] || []
    console.log(`[PlaygroundUIController] Updating models for ${provider}/${api}:`, models.length, 'models')

    // Clear and rebuild model dropdown
    this.modelNameTarget.innerHTML = ''

    if (models.length === 0) {
      const option = document.createElement('option')
      option.value = ''
      option.textContent = 'No models available'
      option.disabled = true
      this.modelNameTarget.appendChild(option)
      return
    }

    // Group models by category
    const modelsByCategory = {}
    models.forEach(model => {
      const category = model.category || 'Other'
      if (!modelsByCategory[category]) {
        modelsByCategory[category] = []
      }
      modelsByCategory[category].push(model)
    })

    // Build options with optgroups
    Object.entries(modelsByCategory).forEach(([category, categoryModels]) => {
      if (Object.keys(modelsByCategory).length > 1 && category !== 'Other') {
        // Create optgroup for multiple categories
        const optgroup = document.createElement('optgroup')
        optgroup.label = category

        categoryModels.forEach(model => {
          const option = document.createElement('option')
          option.value = model.id
          option.textContent = model.name || model.id
          optgroup.appendChild(option)
        })

        this.modelNameTarget.appendChild(optgroup)
      } else {
        // No optgroup for single category or 'Other'
        categoryModels.forEach(model => {
          const option = document.createElement('option')
          option.value = model.id
          option.textContent = model.name || model.id
          this.modelNameTarget.appendChild(option)
        })
      }
    })

    // Select the first model by default
    if (this.modelNameTarget.options.length > 0) {
      this.modelNameTarget.selectedIndex = 0
    }
  }

  /**
   * Update API description text
   */
  updateApiDescription(provider, api) {
    if (!this.hasApiDescriptionTarget || !this.hasModelProviderTarget) return

    const providerData = JSON.parse(this.modelProviderTarget.dataset.providerData || '{}')
    const data = providerData[provider]

    if (!data || !data.apis) return

    const apiConfig = data.apis.find(a => a.key === api)
    if (apiConfig && apiConfig.description) {
      this.apiDescriptionTarget.textContent = apiConfig.description
    }
  }

  // ========== VISIBILITY UPDATE METHODS ==========

  /**
   * Update visibility of all UI panels based on playground_ui configuration
   */
  updatePanelVisibility(playgroundUI) {
    this.updateSystemPromptVisibility(playgroundUI)
    this.updateUserPromptVisibility(playgroundUI)
    this.updateVariablesPreviewVisibility(playgroundUI)
  }

  /**
   * Show/hide system prompt section
   */
  updateSystemPromptVisibility(playgroundUI) {
    if (!this.hasSystemPromptSectionTarget) return

    const show = playgroundUI.includes('system_prompt')
    this.systemPromptSectionTarget.style.display = show ? '' : 'none'
  }

  /**
   * Show/hide user prompt template section
   */
  updateUserPromptVisibility(playgroundUI) {
    if (!this.hasUserPromptTemplateSectionTarget) return

    const show = playgroundUI.includes('user_prompt_template')
    this.userPromptTemplateSectionTarget.style.display = show ? '' : 'none'
  }

  /**
   * Show/hide variables and preview section
   */
  updateVariablesPreviewVisibility(playgroundUI) {
    if (!this.hasVariablesPreviewSectionTarget) return

    const show = playgroundUI.includes('variables') || playgroundUI.includes('preview')
    this.variablesPreviewSectionTarget.style.display = show ? '' : 'none'
  }

  /**
   * Update tools panel visibility and content based on available tools
   *
   * Tools visibility is determined by actual tools data from providerData.tools_by_api,
   * which includes both API builtin_tools and functions (if model supports function_calling).
   *
   * @param {string} provider - Current provider key
   * @param {string} api - Current API key
   */
  updateToolsVisibility(provider, api) {
    if (!this.hasToolsPanelContainerTarget) return

    // Get full tool metadata from providerData (includes builtin tools + functions if supported)
    const toolsData = this.getToolsDataForApi(provider, api)
    const hasTools = toolsData && toolsData.length > 0

    this.toolsPanelContainerTarget.style.display = hasTools ? '' : 'none'

    console.log(`[PlaygroundUIController] Tools panel: ${hasTools ? 'visible' : 'hidden'} (${toolsData.length} tools)`)

    // Update the actual tool cards via outlet
    if (this.hasPlaygroundToolsOutlet) {
      this.playgroundToolsOutlet.updateTools(toolsData)
    }
  }

  /**
   * Get full tool metadata for a provider/API combination from providerData
   *
   * @param {string} provider - Provider key
   * @param {string} api - API key
   * @returns {Array<Object>} Array of tool objects with id, name, description, icon, configurable
   */
  getToolsDataForApi(provider, api) {
    if (!this.hasModelProviderTarget) return []

    const providerData = JSON.parse(this.modelProviderTarget.dataset.providerData || '{}')
    const data = providerData[provider]

    if (!data || !data.tools_by_api) {
      console.warn(`[PlaygroundUIController] No tools_by_api data for provider: ${provider}`)
      return []
    }

    return data.tools_by_api[api] || []
  }

  /**
   * Update conversation panel visibility via outlet
   */
  updateConversationVisibility(playgroundUI) {
    if (!this.hasPlaygroundConversationOutlet) return

    if (playgroundUI.includes('conversation')) {
      this.playgroundConversationOutlet.show()
    } else {
      this.playgroundConversationOutlet.hide()
    }
  }

  /**
   * Update temperature badge when temperature input changes
   */
  onTemperatureChange(event) {
    if (this.hasTemperatureBadgeTarget) {
      this.temperatureBadgeTarget.textContent = event.target.value
    }
  }
}
