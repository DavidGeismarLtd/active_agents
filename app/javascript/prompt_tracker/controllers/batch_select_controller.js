import { Controller } from "@hotwired/stimulus"

/**
 * Batch Select Stimulus Controller
 * Handles select all/one functionality for batch operations on dataset rows
 */
export default class extends Controller {
  static targets = ["selectAll", "checkbox", "batchActions", "selectedCount", "form"]
  static values = {
    batchDeleteUrl: String
  }

  connect() {
    this.updateUI()
  }

  /**
   * Toggle all checkboxes when "select all" is clicked
   */
  toggleAll(event) {
    const isChecked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = isChecked
    })
    this.updateUI()
  }

  /**
   * Handle individual checkbox change
   */
  toggle(event) {
    this.updateUI()
  }

  /**
   * Update UI based on current selection state
   */
  updateUI() {
    const checkedCount = this.selectedIds.length
    const totalCount = this.checkboxTargets.length

    // Update select all checkbox state
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = totalCount > 0 && checkedCount === totalCount
      this.selectAllTarget.indeterminate = checkedCount > 0 && checkedCount < totalCount
    }

    // Show/hide batch actions
    if (this.hasBatchActionsTarget) {
      if (checkedCount > 0) {
        this.batchActionsTarget.classList.remove("d-none")
      } else {
        this.batchActionsTarget.classList.add("d-none")
      }
    }

    // Update selected count display
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = checkedCount
    }
  }

  /**
   * Get array of selected row IDs
   */
  get selectedIds() {
    return this.checkboxTargets
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)
  }

  /**
   * Submit batch delete with confirmation
   */
  batchDelete(event) {
    event.preventDefault()
    
    const selectedIds = this.selectedIds
    if (selectedIds.length === 0) {
      alert("No rows selected for deletion.")
      return
    }

    const confirmMessage = selectedIds.length === 1
      ? "Are you sure you want to delete this row?"
      : `Are you sure you want to delete ${selectedIds.length} rows?`

    if (!confirm(confirmMessage)) {
      return
    }

    // Create and submit a form with the selected IDs
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.batchDeleteUrlValue

    // Add CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const csrfInput = document.createElement("input")
      csrfInput.type = "hidden"
      csrfInput.name = "authenticity_token"
      csrfInput.value = csrfToken
      form.appendChild(csrfInput)
    }

    // Add method override for DELETE
    const methodInput = document.createElement("input")
    methodInput.type = "hidden"
    methodInput.name = "_method"
    methodInput.value = "delete"
    form.appendChild(methodInput)

    // Add selected row IDs
    selectedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "row_ids[]"
      input.value = id
      form.appendChild(input)
    })

    document.body.appendChild(form)
    form.submit()
  }
}

