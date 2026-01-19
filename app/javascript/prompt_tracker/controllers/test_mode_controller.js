import { Controller } from "@hotwired/stimulus"

/**
 * Test Mode Stimulus Controller
 *
 * NOTE: This controller is deprecated as of the evaluator refactoring.
 * All evaluators are now unified and no longer need mode-based filtering.
 * The test form no longer uses this controller, but it's kept for backward
 * compatibility in case any legacy code references it.
 *
 * The controller now simply shows all evaluators without filtering.
 */
export default class extends Controller {
  static targets = ["evaluatorCard", "evaluatorsContainer"]
  static values = {
    testableType: String  // "assistant" or "prompt_version"
  }

  connect() {
    // Show all evaluators - no filtering needed with unified evaluators
    this.showAllEvaluators()
  }

  /**
   * Called when test mode radio button changes (legacy - no longer used)
   */
  modeChanged(_event) {
    // No-op: All evaluators are now unified
    this.showAllEvaluators()
  }

  /**
   * Show all evaluators without filtering
   * All evaluators are now unified (normalized) and work with all test types
   */
  showAllEvaluators() {
    this.evaluatorCardTargets.forEach(card => {
      card.classList.remove("d-none")
    })
  }
}
