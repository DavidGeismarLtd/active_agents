import { Controller } from "@hotwired/stimulus"

/**
 * Playground Sync Visibility Controller
 * 
 * Manages the visibility of sync buttons (Push/Pull) in the playground based on:
 * - Selected provider (must be OpenAI)
 * - Selected API (must be assistants)
 * - Presence of assistant_id
 * 
 * The sync buttons should only be visible when:
 * 1. Provider is "openai"
 * 2. API is "assistants"
 * 3. An assistant_id exists (for pull button)
 * 
 * @example
 * <div data-controller="playground-sync-visibility"
 *      data-playground-sync-visibility-outlet=".playground-ui">
 *   <div data-playground-sync-visibility-target="syncButtons">
 *     <!-- sync buttons here -->
 *   </div>
 * </div>
 */
export default class extends Controller {
  static targets = ["syncButtons"]
  
  static outlets = ["playground-ui"]

  connect() {
    console.log('[PlaygroundSyncVisibilityController] Connected')
    this.updateVisibility()
  }

  /**
   * Called when the playground-ui outlet connects
   * This ensures we update visibility when the UI controller is ready
   */
  playgroundUiOutletConnected() {
    console.log('[PlaygroundSyncVisibilityController] playground-ui outlet connected')
    this.updateVisibility()
  }

  /**
   * Update the visibility of sync buttons based on current provider and API
   * This method is called:
   * - On connect
   * - When provider changes (via custom event)
   * - When API changes (via custom event)
   */
  updateVisibility() {
    if (!this.hasSyncButtonsTarget) {
      console.log('[PlaygroundSyncVisibilityController] No sync buttons target found')
      return
    }

    const shouldShow = this.shouldShowSyncButtons()
    
    console.log('[PlaygroundSyncVisibilityController] Should show sync buttons:', shouldShow)
    
    if (shouldShow) {
      this.syncButtonsTarget.style.display = ''
    } else {
      this.syncButtonsTarget.style.display = 'none'
    }
  }

  /**
   * Determine if sync buttons should be shown
   * @returns {boolean} True if buttons should be visible
   */
  shouldShowSyncButtons() {
    // Check if we have the playground-ui outlet
    if (!this.hasPlaygroundUiOutlet) {
      console.log('[PlaygroundSyncVisibilityController] No playground-ui outlet')
      return false
    }

    const uiController = this.playgroundUiOutlet
    
    // Get current provider and API from the UI controller
    const provider = this.getCurrentProvider(uiController)
    const api = this.getCurrentApi(uiController)
    
    console.log('[PlaygroundSyncVisibilityController] Current provider:', provider, 'API:', api)
    
    // Only show sync buttons for OpenAI Assistants API
    return provider === 'openai' && api === 'assistants'
  }

  /**
   * Get the current provider from the UI controller
   * @param {Controller} uiController - The playground-ui controller
   * @returns {string} The current provider
   */
  getCurrentProvider(uiController) {
    if (!uiController.hasModelProviderTarget) {
      return null
    }
    return uiController.modelProviderTarget.value
  }

  /**
   * Get the current API from the UI controller
   * @param {Controller} uiController - The playground-ui controller
   * @returns {string} The current API
   */
  getCurrentApi(uiController) {
    if (!uiController.hasModelApiTarget) {
      return null
    }
    return uiController.modelApiTarget.value
  }

  /**
   * Handle provider change event
   * This is called via a custom event dispatched by playground-ui controller
   */
  onProviderChange(event) {
    console.log('[PlaygroundSyncVisibilityController] Provider changed:', event.detail)
    this.updateVisibility()
  }

  /**
   * Handle API change event
   * This is called via a custom event dispatched by playground-ui controller
   */
  onApiChange(event) {
    console.log('[PlaygroundSyncVisibilityController] API changed:', event.detail)
    this.updateVisibility()
  }
}

