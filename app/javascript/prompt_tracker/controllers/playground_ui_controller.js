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
 * - conversation: Conversation testing controller
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

  static outlets = ["conversation"]

  connect() {
    console.log('[PlaygroundUIController] Connected')
    // Initialize UI visibility based on current provider/API
    this.updateVisibility()
  }

  // ========== DROPDOWN CHANGE HANDLERS ==========

  /**
   * Handle provider dropdown change
   * Updates API dropdown options and triggers visibility update
   */
  onProviderChange(event) {
    const provider = event.target.value
    console.log(`[PlaygroundUIController] Provider changed to: ${provider}`)

    // Update API dropdown options based on provider
    this.updateApiDropdown(provider)

    // Update visibility
    this.updateVisibility()
  }

  /**
   * Handle API dropdown change
   * Triggers visibility update
   */
  onApiChange(event) {
    const api = event.target.value
    console.log(`[PlaygroundUIController] API changed to: ${api}`)
    debugger
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
    const tools = capabilities.tools || []

    console.log(`[PlaygroundUIController] Capabilities:`, capabilities)

    // Update all UI elements
    this.updatePanelVisibility(playgroundUI)
    this.updateConversationVisibility(playgroundUI)
    this.updateToolsVisibility(tools)
    this.updateApiDescription(provider, api)
  }

  // ========== HELPER METHODS ==========

  /**
   * Get capabilities for a provider/API combination
   *
   * @param {string} provider - Provider name (e.g., 'openai')
   * @param {string} api - API name (e.g., 'assistants')
   * @returns {Object} Capabilities object with playground_ui, tools, features arrays
   */
  getCapabilities(provider, api) {
    if (!this.hasCapabilitiesValue) {
      console.warn('[PlaygroundUIController] No capabilities data available')
      return { playground_ui: [], tools: [], features: [] }
    }

    const capabilities = this.capabilitiesValue
    const providerConfig = capabilities[provider]

    if (!providerConfig) {
      console.warn(`[PlaygroundUIController] Unknown provider: ${provider}`)
      return { playground_ui: [], tools: [], features: [] }
    }

    const apiConfig = providerConfig[api]

    if (!apiConfig) {
      console.warn(`[PlaygroundUIController] Unknown API: ${api} for provider: ${provider}`)
      return { playground_ui: [], tools: [], features: [] }
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

    // Show/hide API select container
    if (this.hasApiSelectContainerTarget) {
      this.apiSelectContainerTarget.style.display = data.apis.length > 1 ? '' : 'none'
    }

    // Update API dropdown options
    if (this.hasModelApiTarget) {
      const currentApi = this.modelApiTarget.value
      this.modelApiTarget.innerHTML = ''

      data.apis.forEach(api => {
        const option = document.createElement('option')
        option.value = api.key
        option.textContent = api.name
        option.dataset.description = api.description
        option.dataset.capabilities = JSON.stringify(api.capabilities)

        // Preserve selection if possible
        if (api.key === currentApi || data.apis.length === 1) {
          option.selected = true
        }

        this.modelApiTarget.appendChild(option)
      })
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
   * Update tools panel visibility based on available tools
   */
  updateToolsVisibility(tools) {
    if (!this.hasToolsPanelContainerTarget) return

    const hasTools = tools && tools.length > 0
    this.toolsPanelContainerTarget.style.display = hasTools ? '' : 'none'

    console.log(`[PlaygroundUIController] Tools panel: ${hasTools ? 'visible' : 'hidden'} (${tools.length} tools)`)
  }

  /**
   * Update conversation panel visibility via outlet
   */
  updateConversationVisibility(playgroundUI) {
    if (!this.hasConversationOutlet) return

    if (playgroundUI.includes('conversation')) {
      this.conversationOutlet.show()
    } else {
      this.conversationOutlet.hide()
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
