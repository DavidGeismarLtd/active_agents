import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Function Editor Controller
 *
 * Manages the function list for OpenAI assistants.
 * Dispatches "functions:changed" event when functions are modified.
 */
export default class extends Controller {
  static targets = [
    "functionList"
  ]

  connect() {
    console.log("Function Editor controller connected")
    this.functions = []
    this.initializeFunctions()
    this.setupModalEventListeners()
  }

  disconnect() {
    this.cleanupModalEventListeners()
  }

  // ========================================
  // Initialization
  // ========================================

  initializeFunctions() {
    if (!this.hasFunctionListTarget) {
      console.warn("Function Editor: functionList target not found")
      return
    }

    const functionItems = this.functionListTarget.querySelectorAll(".function-item")
    console.log(`Function Editor: Found ${functionItems.length} function items in DOM`)

    functionItems.forEach((item, index) => {
      const dataAttr = item.getAttribute("data-function-data")
      if (dataAttr) {
        try {
          // The browser automatically decodes HTML entities in getAttribute()
          // But we need to handle potential edge cases
          const funcData = JSON.parse(dataAttr)

          // Validate the parsed data has required fields
          if (funcData && funcData.name) {
            this.functions.push(funcData)
            console.log(`Function Editor: Loaded function "${funcData.name}"`)
          } else {
            console.warn(`Function Editor: Invalid function data at index ${index}`, funcData)
          }
        } catch (e) {
          console.error(`Function Editor: Failed to parse function data at index ${index}:`, e)
          console.error("Raw data:", dataAttr)
        }
      } else {
        console.warn(`Function Editor: No data-function-data attribute on item ${index}`)
      }
    })

    console.log(`Function Editor: Initialized ${this.functions.length} functions total`)
  }

  setupModalEventListeners() {
    this.boundModalClickHandler = this.handleModalButtonClick.bind(this)
    document.addEventListener("click", this.boundModalClickHandler)
  }

  cleanupModalEventListeners() {
    if (this.boundModalClickHandler) {
      document.removeEventListener("click", this.boundModalClickHandler)
    }
  }

  handleModalButtonClick(event) {
    const saveButton = event.target.closest('[data-action*="function-editor#saveFunction"]')
    if (saveButton) {
      event.preventDefault()
      this.saveFunction()
    }
  }

  // ========================================
  // Public API
  // ========================================

  /**
   * Returns the current list of functions
   * @returns {Array} Array of function objects
   */
  getFunctions() {
    return this.functions
  }

  // ========================================
  // Modal Helpers
  // ========================================

  getModalElement(id) {
    return document.getElementById(id)
  }

  showModal() {
    const modalElement = this.getModalElement("functionEditorModal")
    if (!modalElement) return
    const modal = new Modal(modalElement)
    modal.show()
  }

  hideModal() {
    const modalElement = this.getModalElement("functionEditorModal")
    if (!modalElement) return
    const modal = Modal.getInstance(modalElement)
    if (modal) {
      modal.hide()
    }
  }

  // ========================================
  // Function Actions
  // ========================================

  addFunction() {
    const editIndex = this.getModalElement("functionEditIndex")
    const modalTitle = this.getModalElement("functionModalTitle")
    const saveButtonText = this.getModalElement("functionSaveButtonText")
    const nameInput = this.getModalElement("functionName")
    const descriptionInput = this.getModalElement("functionDescription")
    const parametersInput = this.getModalElement("functionParameters")
    const strictCheckbox = this.getModalElement("functionStrict")

    if (editIndex) editIndex.value = "-1"
    if (modalTitle) modalTitle.textContent = "Add Function"
    if (saveButtonText) saveButtonText.textContent = "Add Function"
    if (nameInput) nameInput.value = ""
    if (descriptionInput) descriptionInput.value = ""
    if (parametersInput) {
      parametersInput.value = JSON.stringify({
        type: "object",
        properties: {},
        required: []
      }, null, 2)
      parametersInput.classList.remove("is-invalid")
    }
    if (strictCheckbox) strictCheckbox.checked = false

    this.showModal()
  }

  editFunction(event) {
    const index = parseInt(event.currentTarget.dataset.functionIndex, 10)
    if (index < 0 || index >= this.functions.length) {
      this.dispatchNotification("error", "Function not found")
      return
    }

    const func = this.functions[index]

    const editIndexInput = this.getModalElement("functionEditIndex")
    const modalTitle = this.getModalElement("functionModalTitle")
    const saveButtonText = this.getModalElement("functionSaveButtonText")
    const nameInput = this.getModalElement("functionName")
    const descriptionInput = this.getModalElement("functionDescription")
    const parametersInput = this.getModalElement("functionParameters")
    const strictCheckbox = this.getModalElement("functionStrict")

    if (editIndexInput) editIndexInput.value = index.toString()
    if (modalTitle) modalTitle.textContent = "Edit Function"
    if (saveButtonText) saveButtonText.textContent = "Update Function"
    if (nameInput) nameInput.value = func.name || ""
    if (descriptionInput) descriptionInput.value = func.description || ""
    if (parametersInput) {
      parametersInput.value = JSON.stringify(func.parameters || {}, null, 2)
      parametersInput.classList.remove("is-invalid")
    }
    if (strictCheckbox) strictCheckbox.checked = func.strict || false

    this.showModal()
  }

  deleteFunction(event) {
    const index = parseInt(event.currentTarget.dataset.functionIndex, 10)
    if (index < 0 || index >= this.functions.length) {
      this.dispatchNotification("error", "Function not found")
      return
    }

    const func = this.functions[index]
    if (!confirm(`Are you sure you want to delete the function "${func.name}"?`)) {
      return
    }

    this.functions.splice(index, 1)
    this.renderFunctionList()
    this.dispatchNotification("success", "Function deleted")
    this.dispatchFunctionsChanged()
  }

  saveFunction() {
    const nameInput = this.getModalElement("functionName")
    const descriptionInput = this.getModalElement("functionDescription")
    const parametersInput = this.getModalElement("functionParameters")
    const parametersError = this.getModalElement("functionParametersError")
    const editIndexInput = this.getModalElement("functionEditIndex")
    const strictCheckbox = this.getModalElement("functionStrict")

    const name = nameInput?.value.trim() || ""
    const description = descriptionInput?.value.trim() || ""
    const parametersText = parametersInput?.value.trim() || ""

    if (!name) {
      this.dispatchNotification("error", "Function name is required")
      nameInput?.focus()
      return
    }

    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name)) {
      this.dispatchNotification("error", "Function name must start with a letter or underscore and contain only alphanumeric characters")
      nameInput?.focus()
      return
    }

    if (!description) {
      this.dispatchNotification("error", "Function description is required")
      descriptionInput?.focus()
      return
    }

    let parameters
    try {
      parameters = JSON.parse(parametersText)
      parametersInput?.classList.remove("is-invalid")
    } catch (e) {
      parametersInput?.classList.add("is-invalid")
      if (parametersError) parametersError.textContent = `Invalid JSON: ${e.message}`
      this.dispatchNotification("error", "Invalid JSON in parameters")
      return
    }

    if (typeof parameters !== "object" || parameters.type !== "object") {
      parametersInput?.classList.add("is-invalid")
      if (parametersError) parametersError.textContent = "Parameters must be a JSON Schema with type 'object'"
      this.dispatchNotification("error", "Parameters must be a JSON Schema with type 'object'")
      return
    }

    const editIndex = parseInt(editIndexInput?.value || "-1", 10)
    const isEditing = editIndex >= 0

    const nameExists = this.functions.some((f, i) => {
      if (isEditing && i === editIndex) return false
      return f.name.toLowerCase() === name.toLowerCase()
    })

    if (nameExists) {
      this.dispatchNotification("error", `A function with the name "${name}" already exists`)
      nameInput?.focus()
      return
    }

    const functionData = {
      name: name,
      description: description,
      parameters: parameters,
      strict: strictCheckbox?.checked || false
    }

    if (isEditing) {
      this.functions[editIndex] = functionData
      this.dispatchNotification("success", "Function updated")
    } else {
      this.functions.push(functionData)
      this.dispatchNotification("success", "Function added")
    }

    this.hideModal()
    this.renderFunctionList()
    this.dispatchFunctionsChanged()
  }

  // ========================================
  // Rendering
  // ========================================

  renderFunctionList() {
    if (!this.hasFunctionListTarget) return

    if (this.functions.length === 0) {
      this.functionListTarget.innerHTML = `
        <div class="text-muted small text-center py-2 empty-functions-message">
          <i class="bi bi-info-circle"></i> No functions defined
        </div>
      `
      return
    }

    const html = this.functions.map((func, index) => {
      const paramCount = Object.keys(func.parameters?.properties || {}).length
      const paramLabel = paramCount === 1 ? "1 parameter" : `${paramCount} parameters`
      const truncatedDesc = func.description?.length > 60
        ? func.description.substring(0, 60) + "..."
        : func.description

      return `
        <div class="function-item card mb-2" data-function-index="${index}" data-function-data='${JSON.stringify(func).replace(/'/g, "&#39;")}'>
          <div class="card-body py-2 px-3">
            <div class="d-flex justify-content-between align-items-start">
              <div class="function-info flex-grow-1">
                <strong class="function-name">${this.escapeHtml(func.name)}</strong>
                <br>
                <small class="text-muted function-description">${this.escapeHtml(truncatedDesc)}</small>
                ${paramCount > 0 ? `<br><small class="text-muted"><i class="bi bi-box"></i> ${paramLabel}</small>` : ""}
              </div>
              <div class="function-actions btn-group btn-group-sm">
                <button type="button"
                        class="btn btn-outline-secondary"
                        data-action="click->function-editor#editFunction"
                        data-function-index="${index}"
                        title="Edit">
                  <i class="bi bi-pencil"></i>
                </button>
                <button type="button"
                        class="btn btn-outline-danger"
                        data-action="click->function-editor#deleteFunction"
                        data-function-index="${index}"
                        title="Delete">
                  <i class="bi bi-trash"></i>
                </button>
              </div>
            </div>
          </div>
        </div>
      `
    }).join("")

    this.functionListTarget.innerHTML = html
  }

  // ========================================
  // Event Dispatching
  // ========================================

  dispatchFunctionsChanged() {
    this.dispatch("changed", {
      detail: { functions: this.functions },
      bubbles: true
    })
  }

  dispatchNotification(type, message) {
    this.dispatch("notification", {
      detail: { type, message },
      bubbles: true
    })
  }

  // ========================================
  // Utilities
  // ========================================

  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
