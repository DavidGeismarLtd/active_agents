import { Controller } from "@hotwired/stimulus"

/**
 * Playground Model Config Controller
 *
 * @description
 * Manages model configuration data collection for the playground.
 * Provides a getModelConfig() method for other controllers to retrieve
 * the current model configuration.
 *
 * @responsibilities
 * - Collect model configuration from form elements
 * - Provide getModelConfig() method for save controller
 *
 * @targets
 * - provider: Provider dropdown
 * - api: API dropdown
 * - model: Model dropdown
 * - temperature: Temperature input
 * - maxTokens: Max tokens input
 * - assistantId: Hidden field for OpenAI assistant_id (preserved during save)
 * - metadata: Hidden field for sync metadata JSON (preserved during save)
 *
 * @public_methods
 * - getModelConfig(): Returns the current model configuration object
 */
export default class extends Controller {
  static targets = ["provider", "api", "model", "temperature", "maxTokens", "assistantId", "metadata"]

  connect() {
    console.log("[PlaygroundModelConfigController] Connected")
    console.log("[PlaygroundModelConfigController] Has provider target?", this.hasProviderTarget)
    console.log("[PlaygroundModelConfigController] Has api target?", this.hasApiTarget)
    console.log("[PlaygroundModelConfigController] Has model target?", this.hasModelTarget)
    console.log("[PlaygroundModelConfigController] Has temperature target?", this.hasTemperatureTarget)
    console.log("[PlaygroundModelConfigController] Has maxTokens target?", this.hasMaxTokensTarget)
    console.log("[PlaygroundModelConfigController] Has assistantId target?", this.hasAssistantIdTarget)
    console.log("[PlaygroundModelConfigController] Has metadata target?", this.hasMetadataTarget)
  }

  /**
   * Get the current model configuration
   * Used by playground-save controller to collect data for saving
   * @returns {Object} Model configuration object
   */
  getModelConfig() {
    const config = {
      provider: this.hasProviderTarget ? this.providerTarget.value : null,
      api: this.hasApiTarget ? this.apiTarget.value : null,
      model: this.hasModelTarget ? this.modelTarget.value : null,
      temperature: this.hasTemperatureTarget ? parseFloat(this.temperatureTarget.value) : 0.7
    }

    // Add max_tokens if set
    if (this.hasMaxTokensTarget && this.maxTokensTarget.value) {
      config.max_tokens = parseInt(this.maxTokensTarget.value)
    }

    // Preserve assistant_id from hidden field (for OpenAI Assistants sync)
    if (this.hasAssistantIdTarget && this.assistantIdTarget.value) {
      config.assistant_id = this.assistantIdTarget.value
    }

    // Preserve metadata from hidden field (stored as JSON)
    if (this.hasMetadataTarget && this.metadataTarget.value) {
      try {
        config.metadata = JSON.parse(this.metadataTarget.value)
      } catch (e) {
        console.warn("[PlaygroundModelConfigController] Failed to parse metadata JSON:", e)
      }
    }

    console.log("[PlaygroundModelConfigController] getModelConfig():", config)
    return config
  }
}
