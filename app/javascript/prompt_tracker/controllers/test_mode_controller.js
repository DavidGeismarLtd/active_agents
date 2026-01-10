import { Controller } from "@hotwired/stimulus"

/**
 * Test Mode Stimulus Controller
 * Handles dynamic filtering of evaluators based on test mode selection
 */
export default class extends Controller {
  static targets = ["evaluatorCard", "evaluatorsContainer"]
  static values = {
    testableType: String  // "assistant" or "prompt_version"
  }

  connect() {
    // Apply initial filtering based on current test mode
    this.filterEvaluators()
  }

  /**
   * Called when test mode radio button changes
   */
  modeChanged(event) {
    this.filterEvaluators()
  }

  /**
   * Filter evaluators based on current test mode
   */
  filterEvaluators() {
    const selectedMode = this.getSelectedMode()

    this.evaluatorCardTargets.forEach(card => {
      const apiType = card.dataset.apiType
      const shouldShow = this.shouldShowEvaluator(apiType, selectedMode)

      if (shouldShow) {
        card.classList.remove("d-none")
      } else {
        card.classList.add("d-none")
        // Uncheck the evaluator if it's hidden
        const checkbox = card.querySelector('input[type="checkbox"]')
        if (checkbox && checkbox.checked) {
          checkbox.checked = false
          // Trigger change event to update the hidden field
          checkbox.dispatchEvent(new Event('change', { bubbles: true }))
        }
      }
    })
  }

  /**
   * Get the currently selected test mode
   */
  getSelectedMode() {
    // First check radio buttons within this form
    const form = this.element
    const singleTurnRadio = form.querySelector('input[type="radio"][id="test_mode_single_turn"]')
    const conversationalRadio = form.querySelector('input[type="radio"][id="test_mode_conversational"]')

    // If radio buttons exist, use their value
    if (singleTurnRadio || conversationalRadio) {
      if (singleTurnRadio && singleTurnRadio.checked) {
        return "single_turn"
      }
      if (conversationalRadio && conversationalRadio.checked) {
        return "conversational"
      }
      // Default to single_turn if radios exist but none selected
      return "single_turn"
    }

    // Check for hidden field (used when mode is forced, e.g., for assistants)
    const hiddenField = form.querySelector('input[type="hidden"][name$="[test_mode]"]')
    if (hiddenField) {
      return hiddenField.value
    }

    // Default to single_turn
    return "single_turn"
  }

  /**
   * Determine if an evaluator should be shown based on its API type and the selected mode
   */
  shouldShowEvaluator(apiType, selectedMode) {
    if (selectedMode === "single_turn") {
      // Only show chat_completion evaluators
      return apiType === "chat_completion"
    } else {
      // Conversational mode
      if (this.testableTypeValue === "assistant") {
        // Show all conversational evaluators (including assistants_api)
        return apiType === "conversational" || apiType === "assistants_api"
      } else {
        // PromptVersion in conversational mode - exclude assistants_api
        return apiType === "conversational"
      }
    }
  }
}
