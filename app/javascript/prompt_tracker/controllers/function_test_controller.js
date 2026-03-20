import { Controller } from "@hotwired/stimulus"

/**
 * Function Test Controller
 *
 * @description
 * Handles testing functions with custom arguments via AJAX.
 * Displays results inline without page reload.
 *
 * @responsibilities
 * - Submit test form via AJAX
 * - Display loading state
 * - Show test results (success or error)
 * - Load example input
 */
export default class extends Controller {
  static targets = ["form", "submitButton", "result", "resultContent"]

  connect() {
    console.log("[FunctionTestController] Connected")

    // Intercept form submission
    this.formTarget.addEventListener("submit", this.handleSubmit.bind(this))
  }

  /**
   * Handle form submission via AJAX
   */
  async handleSubmit(event) {
    event.preventDefault()

    const form = this.formTarget
    const url = form.action

    // Get arguments from the textarea (Monaco editor syncs to it)
    const argumentsTextarea = form.querySelector('textarea[name="arguments"]')
    const argumentsValue = argumentsTextarea ? argumentsTextarea.value : "{}"

    // Get CSRF token from meta tag
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Show loading state
    this.showLoading()

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          arguments: argumentsValue
        }),
        credentials: 'same-origin'
      })

      const data = await response.json()

      if (response.ok) {
        this.showSuccess(data)
      } else {
        // Check if it's a deployment status error
        if (data.deployment_status && data.deployment_status !== "deployed") {
          this.showDeploymentRequired(data.error)
        } else {
          this.showError(data.error || "Test failed")
        }
      }
    } catch (error) {
      this.showError(`Network error: ${error.message}`)
    }
  }

  /**
   * Show loading state
   */
  showLoading() {
    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Running...'

    this.resultTarget.style.display = "block"
    this.resultContentTarget.innerHTML = `
      <div class="alert alert-info">
        <div class="d-flex align-items-center">
          <div class="spinner-border spinner-border-sm me-3" role="status"></div>
          <div>
            <strong>Deploying to AWS Lambda...</strong>
            <div class="small">This may take a few seconds on first run</div>
          </div>
        </div>
      </div>
    `
  }

  /**
   * Show success result
   */
  showSuccess(data) {
    this.submitButtonTarget.disabled = false
    this.submitButtonTarget.innerHTML = '<i class="bi bi-play-circle"></i> Run Test'

    const executionTime = data.execution_time_ms || 0
    const result = data.result || data

    this.resultContentTarget.innerHTML = `
      <div class="alert alert-success">
        <div class="d-flex justify-content-between align-items-center mb-2">
          <strong><i class="bi bi-check-circle"></i> Test Passed</strong>
          <span class="badge bg-success">${executionTime}ms</span>
        </div>
        <div class="small text-muted mb-2">Function executed successfully on AWS Lambda</div>
      </div>

      <div class="card">
        <div class="card-header">
          <strong>Result</strong>
        </div>
        <div class="card-body">
          <pre class="bg-light p-3 rounded mb-0"><code class="language-json">${JSON.stringify(result, null, 2)}</code></pre>
        </div>
      </div>
    `
  }

  /**
   * Show deployment required message
   */
  showDeploymentRequired(errorMessage) {
    this.submitButtonTarget.disabled = false
    this.submitButtonTarget.innerHTML = '<i class="bi bi-play-circle"></i> Run Test'

    this.resultContentTarget.innerHTML = `
      <div class="alert alert-warning">
        <h5 class="alert-heading"><i class="bi bi-exclamation-triangle"></i> Deployment Required</h5>
        <p class="mb-3">${this.escapeHtml(errorMessage)}</p>
        <hr>
        <p class="mb-0">
          <strong>Next step:</strong> Scroll up and click the <strong>"Publish to Lambda"</strong> button to deploy this function to AWS Lambda.
        </p>
      </div>
    `
  }

  /**
   * Show error result
   */
  showError(errorMessage) {
    this.submitButtonTarget.disabled = false
    this.submitButtonTarget.innerHTML = '<i class="bi bi-play-circle"></i> Run Test'

    this.resultContentTarget.innerHTML = `
      <div class="alert alert-danger">
        <strong><i class="bi bi-x-circle"></i> Test Failed</strong>
        <div class="mt-2">
          <pre class="mb-0 text-danger">${this.escapeHtml(errorMessage)}</pre>
        </div>
      </div>

      <div class="card border-danger">
        <div class="card-header bg-danger text-white">
          <strong>Error Details</strong>
        </div>
        <div class="card-body">
          <p class="mb-2"><strong>Common issues:</strong></p>
          <ul class="mb-0">
            <li>Check that your AWS credentials are configured correctly</li>
            <li>Verify the Lambda execution role ARN is correct</li>
            <li>Ensure your code syntax is valid Ruby</li>
            <li>Check that required gems are listed in dependencies</li>
          </ul>
        </div>
      </div>
    `
  }

  /**
   * Load example input into the form
   */
  loadExample(event) {
    event.preventDefault()

    // Find the Monaco editor controller
    const monacoContainer = this.element.querySelector('[data-controller="monaco-editor"]')
    if (monacoContainer) {
      const monacoController = this.application.getControllerForElementAndIdentifier(
        monacoContainer,
        "monaco-editor"
      )

      if (monacoController && monacoController.editor) {
        // Get example input from data attribute or default
        const exampleInput = this.element.dataset.exampleInput || "{}"
        monacoController.editor.setValue(exampleInput)
      }
    }
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
