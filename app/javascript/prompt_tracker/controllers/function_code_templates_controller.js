import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

/**
 * Function Code Templates Controller
 *
 * @description
 * Provides code templates and snippets for common function patterns.
 * Allows users to quickly start with a template instead of writing from scratch.
 *
 * @responsibilities
 * - Display template selection modal
 * - Insert selected template into Monaco Editor
 * - Provide common patterns (API call, data processing, validation, etc.)
 *
 * @outlets
 * - monacoEditor: The Monaco Editor controller to insert code into
 */
export default class extends Controller {
  static outlets = ["monaco-editor"]

  // Code templates for common function patterns
  templates = {
    basic: {
      name: "Basic Function",
      description: "Simple function template with argument handling",
      code: `# Basic function template
def execute(args)
  # Extract arguments
  name = args[:name] || args["name"]

  # Your logic here
  result = "Hello, #{name}!"

  # Return result
  { message: result }
end`
    },

    api_call: {
      name: "API Call",
      description: "Make HTTP requests to external APIs",
      code: `# API call function
require 'net/http'
require 'json'

def execute(args)
  # Get API endpoint from arguments
  endpoint = args[:endpoint] || args["endpoint"]

  # Get API key from environment variables
  api_key = ENV['API_KEY']

  # Make HTTP request
  uri = URI(endpoint)
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{api_key}"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(request)
  end

  # Parse and return response
  if response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    { error: "API request failed", status: response.code }
  end
end`
    },

    data_processing: {
      name: "Data Processing",
      description: "Process and transform data",
      code: `# Data processing function
def execute(args)
  # Get data from arguments
  data = args[:data] || args["data"] || []

  # Process data
  processed = data.map do |item|
    # Transform each item
    {
      id: item[:id] || item["id"],
      value: (item[:value] || item["value"]).to_s.upcase,
      timestamp: Time.now.iso8601
    }
  end

  # Return processed data
  {
    count: processed.length,
    items: processed
  }
end`
    },

    validation: {
      name: "Validation",
      description: "Validate input data",
      code: `# Validation function
def execute(args)
  # Get data to validate
  email = args[:email] || args["email"]

  # Validation rules
  errors = []

  if email.nil? || email.empty?
    errors << "Email is required"
  elsif !email.match?(/\\A[\\w+\\-.]+@[a-z\\d\\-]+(\\.[a-z\\d\\-]+)*\\.[a-z]+\\z/i)
    errors << "Email format is invalid"
  end

  # Return validation result
  {
    valid: errors.empty?,
    errors: errors,
    data: { email: email }
  }
end`
    },

    conditional_logic: {
      name: "Conditional Logic",
      description: "Execute different logic based on conditions",
      code: `# Conditional logic function
def execute(args)
  # Get action type
  action = args[:action] || args["action"]
  value = args[:value] || args["value"]

  # Execute based on action
  case action
  when "uppercase"
    { result: value.to_s.upcase }
  when "lowercase"
    { result: value.to_s.downcase }
  when "reverse"
    { result: value.to_s.reverse }
  when "length"
    { result: value.to_s.length }
  else
    { error: "Unknown action: #{action}" }
  end
end`
    }
  }

  connect() {
    console.log("[FunctionCodeTemplatesController] Connected")
  }

  /**
   * Show template selection modal
   */
  showTemplates(event) {
    event.preventDefault()
    console.log("[FunctionCodeTemplates] showTemplates called")

    // Remove focus from button to prevent aria-hidden focus conflict
    if (event.target) {
      event.target.blur()
    }

    // Build modal HTML
    const modalHTML = this.buildTemplateModal()

    // Create wrapper with modal-fix controller
    const modalContainer = document.createElement("div")
    modalContainer.innerHTML = modalHTML

    const modalElement = modalContainer.querySelector(".modal")

    // Add modal-fix attributes BEFORE appending to DOM
    modalContainer.setAttribute("data-controller", "modal-fix")
    modalElement.setAttribute("data-modal-fix-target", "modal")

    console.log("[FunctionCodeTemplates] Appending modal to body")
    // Now append to body (this will trigger Stimulus to connect the controller)
    document.body.appendChild(modalContainer)

    // Add click event listeners to template cards
    modalElement.querySelectorAll(".template-card").forEach(card => {
      card.addEventListener("click", (e) => {
        console.log("[FunctionCodeTemplates] Template card clicked:", e.currentTarget.dataset.templateKey)
        const templateKey = e.currentTarget.dataset.templateKey
        this.insertTemplate(templateKey)
        console.log("[FunctionCodeTemplates] Hiding modal")
        const modal = bootstrap.Modal.getInstance(modalElement)
        if (modal) modal.hide()
      })
    })

    // Show modal after a brief delay to ensure DOM is ready
    setTimeout(() => {
      console.log("[FunctionCodeTemplates] Showing modal")
      const modal = new bootstrap.Modal(modalElement, {
        backdrop: true,
        keyboard: true,
        focus: true
      })
      modal.show()
    }, 10)

    // Clean up when modal is hidden
    modalElement.addEventListener("hidden.bs.modal", () => {
      console.log("[FunctionCodeTemplates] Modal hidden, cleaning up")
      modalContainer.remove()
    })
  }

  /**
   * Build template selection modal HTML
   */
  buildTemplateModal() {
    const templateCards = Object.entries(this.templates).map(([key, template]) => `
      <div class="col-md-6 mb-3">
        <div class="card h-100 template-card" style="cursor: pointer;" data-template-key="${key}">
          <div class="card-body">
            <h6 class="card-title">
              <i class="bi bi-file-code"></i> ${template.name}
            </h6>
            <p class="card-text text-muted small">${template.description}</p>
          </div>
        </div>
      </div>
    `).join("")

    return `
      <div class="modal fade" tabindex="-1">
        <div class="modal-dialog modal-lg">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">
                <i class="bi bi-file-code"></i> Select Code Template
              </h5>
              <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
              <p class="text-muted">Choose a template to get started quickly:</p>
              <div class="row">
                ${templateCards}
              </div>
            </div>
          </div>
        </div>
      </div>
    `
  }

  /**
   * Insert template code into Monaco Editor
   */
  insertTemplate(templateKey) {
    const template = this.templates[templateKey]

    if (template && this.hasMonacoEditorOutlet) {
      // Insert template code into Monaco Editor
      this.monacoEditorOutlet.setValue(template.code)
    }
  }

  /**
   * Insert selected template into Monaco Editor (kept for backwards compatibility)
   */
  selectTemplate(event) {
    const templateKey = event.currentTarget.dataset.templateKey
    this.insertTemplate(templateKey)

    // Close modal
    const modal = bootstrap.Modal.getInstance(event.currentTarget.closest(".modal"))
    if (modal) modal.hide()
  }
}
