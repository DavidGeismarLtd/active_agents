import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Tools Configuration Controller
 * Manages Response API tools configuration including:
 * - File Search with vector store selection
 * - Custom function definitions
 */
export default class extends Controller {
  static targets = [
    "toolCheckbox",
    "fileSearchPanel",
    "vectorStoreSelect",
    "selectedVectorStores",
    "vectorStoreCount",
    "vectorStoreAddButton",
    "vectorStoreError",
    "functionsPanel",
    "functionsList",
    "functionItem",
    "noFunctionsMessage",
    // Create vector store modal targets
    "createVectorStoreModal",
    "vectorStoreName",
    "vectorStoreFiles",
    "createVectorStoreStatus",
    "createVectorStoreStatusText",
    "createVectorStoreError",
    "createVectorStoreErrorText",
    "createVectorStoreButton",
    // Vector store files modal targets
    "vectorStoreFilesModal",
    "vectorStoreFilesModalTitle",
    "vectorStoreFilesLoading",
    "vectorStoreFilesError",
    "vectorStoreFilesErrorText",
    "vectorStoreFilesList"
  ]

  // OpenAI Responses API hard limit
  static MAX_VECTOR_STORES = 2

  connect() {
    this.vectorStoresLoaded = false
    // Defer initial update to ensure DOM is fully ready
    requestAnimationFrame(() => {
      this.updatePanelVisibility()
      this.updateVectorStoreCount()
      this.checkVectorStoreLimit()
    })
  }

  /**
   * Handle tool checkbox toggle
   */
  onToolToggle(event) {
    const checkbox = event.target
    const toolId = checkbox.dataset.toolId
    const isConfigurable = checkbox.dataset.configurable === "true"

    if (isConfigurable) {
      this.updatePanelVisibility()

      // Load vector stores when file_search is enabled
      if (toolId === "file_search" && checkbox.checked && !this.vectorStoresLoaded) {
        this.loadVectorStores()
      }
    }

    this.dispatchToolConfigChange()
  }

  /**
   * Update visibility of configuration panels based on checkbox state
   */
  updatePanelVisibility() {
    // If no targets found via Stimulus, try querying the DOM directly
    let checkboxes = this.toolCheckboxTargets
    if (checkboxes.length === 0) {
      checkboxes = this.element.querySelectorAll('input[type="checkbox"][data-tool-id]')
    }

    checkboxes.forEach(checkbox => {
      const toolId = checkbox.dataset.toolId

      if (toolId === "file_search" && this.hasFileSearchPanelTarget) {
        this.fileSearchPanelTarget.classList.toggle("show", checkbox.checked)
      }

      if (toolId === "functions" && this.hasFunctionsPanelTarget) {
        this.functionsPanelTarget.classList.toggle("show", checkbox.checked)
      }
    })
  }

  /**
   * Load available vector stores from the API
   */
  async loadVectorStores(event) {
    if (event) event.preventDefault()

    const select = this.vectorStoreSelectTarget
    select.disabled = true
    select.innerHTML = '<option value="">Loading...</option>'

    try {
      const response = await fetch("/prompt_tracker/api/vector_stores")
      if (!response.ok) throw new Error("Failed to load vector stores")

      const data = await response.json()
      select.innerHTML = '<option value="">Select a vector store...</option>'

      // Get already selected store IDs
      const selectedIds = Array.from(
        this.selectedVectorStoresTarget.querySelectorAll("[data-vector-store-id]")
      ).map(el => el.dataset.vectorStoreId)

      data.vector_stores.forEach(store => {
        // Skip already selected stores
        if (selectedIds.includes(store.id)) return

        const option = document.createElement("option")
        option.value = store.id
        option.textContent = store.name || store.id
        select.appendChild(option)
      })

      this.vectorStoresLoaded = true
    } catch (error) {
      console.error("Error loading vector stores:", error)
      select.innerHTML = '<option value="">Error loading stores</option>'
    } finally {
      select.disabled = false
    }
  }

  /**
   * Add selected vector store to the list
   */
  addVectorStore() {
    const select = this.vectorStoreSelectTarget
    const selectedOption = select.options[select.selectedIndex]
    const storeId = select.value
    const storeName = selectedOption?.textContent || storeId
    if (!storeId) return

    // Check if already added
    const existing = this.selectedVectorStoresTarget.querySelector(`[data-vector-store-id="${storeId}"]`)
    if (existing) return

    // Check vector store limit
    const currentCount = this.getVectorStoreCount()
    if (currentCount >= this.constructor.MAX_VECTOR_STORES) {
      this.showVectorStoreError(`Maximum ${this.constructor.MAX_VECTOR_STORES} vector stores allowed for OpenAI Responses API`)
      return
    }

    const badge = document.createElement("span")
    badge.className = "badge bg-primary d-flex align-items-center gap-1"
    badge.dataset.vectorStoreId = storeId
    badge.dataset.vectorStoreName = storeName
    badge.style.cursor = "pointer"
    badge.dataset.action = "click->tools-config#showVectorStoreFiles"
    badge.title = "Click to view files"
    badge.innerHTML = `
      <span class="vector-store-name">${this.escapeHtml(storeName)}</span>
      <button type="button" class="btn-close btn-close-white" style="font-size: 0.6rem;"
              data-action="click->tools-config#removeVectorStore"
              onclick="event.stopPropagation()"></button>
    `

    this.selectedVectorStoresTarget.appendChild(badge)

    // Remove the option from the select to prevent duplicate additions
    selectedOption.remove()
    select.value = ""

    this.updateVectorStoreCount()
    this.updateAddButtonState()
    this.dispatchToolConfigChange()
  }

  /**
   * Remove a vector store from the selection
   */
  removeVectorStore(event) {
    const badge = event.target.closest("[data-vector-store-id]")
    const storeId = badge.dataset.vectorStoreId
    const storeName = badge.dataset.vectorStoreName || storeId

    // Add the option back to the select
    const select = this.vectorStoreSelectTarget
    const option = document.createElement("option")
    option.value = storeId
    option.textContent = storeName
    select.appendChild(option)

    badge.remove()
    this.updateVectorStoreCount()
    this.updateAddButtonState()
    this.hideVectorStoreError()
    this.dispatchToolConfigChange()
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Show the create vector store modal
   */
  showCreateVectorStoreModal() {
    if (!this.hasCreateVectorStoreModalTarget) return

    const modalEl = this.createVectorStoreModalTarget

    // Move modal to end of body to fix z-index issues with backdrop
    if (!modalEl.hasAttribute('data-moved-to-body')) {
      document.body.appendChild(modalEl)
      modalEl.setAttribute('data-moved-to-body', 'true')
    }

    // Reset form
    if (this.hasVectorStoreNameTarget) this.vectorStoreNameTarget.value = ""
    if (this.hasVectorStoreFilesTarget) this.vectorStoreFilesTarget.value = ""
    if (this.hasCreateVectorStoreStatusTarget) this.createVectorStoreStatusTarget.classList.add("d-none")
    if (this.hasCreateVectorStoreErrorTarget) this.createVectorStoreErrorTarget.classList.add("d-none")
    if (this.hasCreateVectorStoreButtonTarget) this.createVectorStoreButtonTarget.disabled = false

    const modal = new Modal(modalEl)
    modal.show()
  }

  /**
   * Create a new vector store with uploaded files
   */
  async createVectorStore() {
    const name = this.vectorStoreNameTarget?.value?.trim()
    const files = this.vectorStoreFilesTarget?.files

    // Validate
    if (!name) {
      this.showCreateError("Please enter a name for the vector store.")
      return
    }
    if (!files || files.length === 0) {
      this.showCreateError("Please select at least one file to upload.")
      return
    }

    // Check vector store limit before creating
    const currentCount = this.getVectorStoreCount()
    if (currentCount >= this.constructor.MAX_VECTOR_STORES) {
      this.showCreateError(`Maximum ${this.constructor.MAX_VECTOR_STORES} vector stores allowed. Please remove one before creating a new one.`)
      return
    }

    // Show progress
    this.createVectorStoreButtonTarget.disabled = true
    this.createVectorStoreStatusTarget.classList.remove("d-none")
    this.createVectorStoreErrorTarget.classList.add("d-none")
    this.createVectorStoreStatusTextTarget.textContent = "Uploading files..."

    try {
      // Create FormData with files
      const formData = new FormData()
      formData.append("name", name)
      for (let i = 0; i < files.length; i++) {
        formData.append("files[]", files[i])
      }

      this.createVectorStoreStatusTextTarget.textContent = "Creating vector store..."

      const response = await fetch("/prompt_tracker/api/vector_stores", {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || "Failed to create vector store")
      }

      const data = await response.json()
      this.createVectorStoreStatusTextTarget.textContent = "Vector store created!"

      // Add the new vector store to the selected list
      const badge = document.createElement("span")
      badge.className = "badge bg-primary d-flex align-items-center gap-1"
      badge.dataset.vectorStoreId = data.id
      badge.dataset.vectorStoreName = data.name
      badge.style.cursor = "pointer"
      badge.dataset.action = "click->tools-config#showVectorStoreFiles"
      badge.title = "Click to view files"
      badge.innerHTML = `
        <span class="vector-store-name">${this.escapeHtml(data.name)}</span>
        <button type="button" class="btn-close btn-close-white" style="font-size: 0.6rem;"
                data-action="click->tools-config#removeVectorStore"
                onclick="event.stopPropagation()"></button>
      `
      this.selectedVectorStoresTarget.appendChild(badge)

      // Close modal after short delay
      setTimeout(() => {
        Modal.getInstance(this.createVectorStoreModalTarget)?.hide()
      }, 500)

      this.updateVectorStoreCount()
      this.updateAddButtonState()
      this.dispatchToolConfigChange()

      // Reload vector stores to update the list
      this.vectorStoresLoaded = false
      await this.loadVectorStores()

    } catch (error) {
      console.error("Error creating vector store:", error)
      this.showCreateError(error.message)
    } finally {
      this.createVectorStoreButtonTarget.disabled = false
    }
  }

  /**
   * Show error in the create modal
   */
  showCreateError(message) {
    if (this.hasCreateVectorStoreErrorTarget) {
      this.createVectorStoreErrorTextTarget.textContent = message
      this.createVectorStoreErrorTarget.classList.remove("d-none")
    }
    if (this.hasCreateVectorStoreStatusTarget) {
      this.createVectorStoreStatusTarget.classList.add("d-none")
    }
  }

  /**
   * Get current vector store count
   */
  getVectorStoreCount() {
    if (!this.hasSelectedVectorStoresTarget) return 0
    return this.selectedVectorStoresTarget.querySelectorAll("[data-vector-store-id]").length
  }

  /**
   * Update vector store count display
   */
  updateVectorStoreCount() {
    if (!this.hasVectorStoreCountTarget) return
    const count = this.getVectorStoreCount()
    this.vectorStoreCountTarget.textContent = count
  }

  /**
   * Update add button state based on vector store limit
   */
  updateAddButtonState() {
    if (!this.hasVectorStoreAddButtonTarget) return

    const currentCount = this.getVectorStoreCount()
    const atLimit = currentCount >= this.constructor.MAX_VECTOR_STORES

    this.vectorStoreAddButtonTarget.disabled = atLimit

    if (atLimit) {
      this.vectorStoreAddButtonTarget.title = `Maximum ${this.constructor.MAX_VECTOR_STORES} vector stores allowed`
    } else {
      this.vectorStoreAddButtonTarget.title = "Add selected store"
    }
  }

  /**
   * Show vector store error message
   */
  showVectorStoreError(message) {
    if (!this.hasVectorStoreErrorTarget) return
    this.vectorStoreErrorTarget.textContent = message
    this.vectorStoreErrorTarget.classList.remove("d-none")

    // Auto-hide after 5 seconds
    setTimeout(() => {
      this.hideVectorStoreError()
    }, 5000)
  }

  /**
   * Hide vector store error message
   */
  hideVectorStoreError() {
    if (!this.hasVectorStoreErrorTarget) return
    this.vectorStoreErrorTarget.classList.add("d-none")
  }

  /**
   * Check vector store limit on page load and show warning if exceeded
   */
  checkVectorStoreLimit() {
    const currentCount = this.getVectorStoreCount()

    if (currentCount > this.constructor.MAX_VECTOR_STORES) {
      // Show warning for existing configurations with too many stores
      const warningMessage = `⚠️ Warning: ${currentCount} vector stores configured, but OpenAI Responses API only supports ${this.constructor.MAX_VECTOR_STORES}. Only the first ${this.constructor.MAX_VECTOR_STORES} will be used.`
      this.showVectorStoreError(warningMessage)

      // Disable add button
      this.updateAddButtonState()
    }
  }

  /**
   * Add a new function definition
   */
  addFunction() {
    if (this.hasNoFunctionsMessageTarget) {
      this.noFunctionsMessageTarget.remove()
    }

    const index = this.functionItemTargets.length
    const template = this.createFunctionTemplate(index)
    this.functionsListTarget.insertAdjacentHTML("beforeend", template)
    this.dispatchToolConfigChange()
  }

  /**
   * Create HTML template for a new function item
   */
  createFunctionTemplate(index) {
    return `
      <div class="function-item card mb-2" data-tools-config-target="functionItem" data-function-index="${index}">
        <div class="card-body p-2">
          <div class="d-flex justify-content-between align-items-start mb-2">
            <div class="flex-grow-1 me-2">
              <input type="text"
                     class="form-control form-control-sm mb-1"
                     placeholder="Function name (e.g., get_weather)"
                     data-tools-config-target="functionName"
                     data-action="input->tools-config#onFunctionChange">
              <input type="text"
                     class="form-control form-control-sm mb-2"
                     placeholder="Description"
                     data-tools-config-target="functionDescription"
                     data-action="input->tools-config#onFunctionChange">
              <textarea class="form-control form-control-sm"
                        rows="2"
                        placeholder="Output description (e.g., Returns a JSON object with temperature, condition, and humidity fields)"
                        data-tools-config-target="functionOutputDescription"
                        data-action="input->tools-config#onFunctionChange"></textarea>
              <div class="form-text small">
                Describe what this function returns to help generate better mock outputs
              </div>
            </div>
            <button type="button"
                    class="btn btn-sm btn-outline-danger"
                    data-action="click->tools-config#removeFunction">
              <i class="bi bi-trash"></i>
            </button>
          </div>

          <div class="mb-2">
            <label class="form-label small mb-1">Parameters (JSON Schema)</label>
            <textarea class="form-control form-control-sm font-monospace"
                      rows="4"
                      placeholder='{"type": "object", "properties": {...}, "required": [...]}'
                      data-tools-config-target="functionParameters"
                      data-action="input->tools-config#onFunctionChange"></textarea>
          </div>

          <div class="form-check form-check-inline">
            <input type="checkbox"
                   class="form-check-input"
                   id="strict_${index}"
                   data-tools-config-target="functionStrict"
                   data-action="change->tools-config#onFunctionChange">
            <label class="form-check-label small" for="strict_${index}">
              Strict mode (enforce schema)
            </label>
          </div>
        </div>
      </div>
    `
  }

  /**
   * Remove a function definition
   */
  removeFunction(event) {
    event.target.closest(".function-item").remove()

    // Show "no functions" message if list is empty
    if (this.functionItemTargets.length === 0) {
      this.functionsListTarget.innerHTML = `
        <div class="text-muted text-center py-3" data-tools-config-target="noFunctionsMessage">
          <i class="bi bi-info-circle"></i>
          No functions defined. Click "Add Function" to create one.
        </div>
      `
    }

    this.dispatchToolConfigChange()
  }

  /**
   * Handle function field changes
   */
  onFunctionChange() {
    this.dispatchToolConfigChange()
  }

  /**
   * Get the current tool configuration
   */
  getToolConfig() {
    const config = {
      enabled_tools: [],
      tool_config: {}
    }

    // Collect enabled tools
    this.toolCheckboxTargets.forEach(checkbox => {
      if (checkbox.checked) {
        config.enabled_tools.push(checkbox.dataset.toolId)
      }
    })

    // Collect file_search config
    if (this.hasSelectedVectorStoresTarget) {
      const vectorStores = []
      this.selectedVectorStoresTarget.querySelectorAll("[data-vector-store-id]").forEach(badge => {
        vectorStores.push({
          id: badge.dataset.vectorStoreId,
          name: badge.dataset.vectorStoreName || badge.dataset.vectorStoreId
        })
      })
      if (vectorStores.length > 0) {
        // Only use first MAX_VECTOR_STORES for backward compatibility
        const limitedVectorStores = vectorStores.slice(0, this.constructor.MAX_VECTOR_STORES)

        config.tool_config.file_search = {
          vector_store_ids: limitedVectorStores.map(vs => vs.id),
          vector_stores: limitedVectorStores
        }
      }
    }

    // Collect functions config
    const functions = []
    this.functionItemTargets.forEach(item => {
      const nameInput = item.querySelector('[data-tools-config-target="functionName"]')
      const descInput = item.querySelector('[data-tools-config-target="functionDescription"]')
      const outputDescInput = item.querySelector('[data-tools-config-target="functionOutputDescription"]')
      const paramsInput = item.querySelector('[data-tools-config-target="functionParameters"]')
      const strictInput = item.querySelector('[data-tools-config-target="functionStrict"]')

      const name = nameInput?.value?.trim()
      if (!name) return

      let parameters = {}
      try {
        const paramsText = paramsInput?.value?.trim()
        if (paramsText) {
          parameters = JSON.parse(paramsText)
        }
      } catch (e) {
        console.warn("Invalid JSON in function parameters:", e)
      }

      const func = {
        name: name,
        description: descInput?.value?.trim() || "",
        parameters: parameters,
        strict: strictInput?.checked || false
      }

      // Add output_description if present
      const outputDesc = outputDescInput?.value?.trim()
      if (outputDesc) {
        func.output_description = outputDesc
      }

      functions.push(func)
    })

    if (functions.length > 0) {
      config.tool_config.functions = functions
    }

    return config
  }

  /**
   * Dispatch custom event with tool configuration
   */
  dispatchToolConfigChange() {
    const config = this.getToolConfig()
    this.dispatch("change", { detail: config })
  }

  /**
   * Show vector store files modal
   */
  async showVectorStoreFiles(event) {
    // Stop propagation to prevent badge removal
    event.stopPropagation()

    const badge = event.currentTarget
    const vectorStoreId = badge.dataset.vectorStoreId
    const vectorStoreName = badge.dataset.vectorStoreName || vectorStoreId

    // Get modal element - either from target or from document if already moved
    let modalEl = this.hasVectorStoreFilesModalTarget
      ? this.vectorStoreFilesModalTarget
      : document.getElementById('vectorStoreFilesModal')

    if (!modalEl) {
      console.error("Vector store files modal not found")
      return
    }

    // Move modal to end of body to fix z-index issues with backdrop
    if (!modalEl.hasAttribute('data-moved-to-body')) {
      document.body.appendChild(modalEl)
      modalEl.setAttribute('data-moved-to-body', 'true')
    }

    // Update modal title using direct DOM query (since modal may be moved to body)
    const titleEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesModalTitle"]')
    if (titleEl) {
      titleEl.textContent = `Files in ${vectorStoreName}`
    }

    // Show modal
    const modal = new Modal(modalEl)
    modal.show()

    // Show loading state
    this.showFilesLoading(modalEl)

    try {
      // Fetch files from API
      const response = await fetch(`/prompt_tracker/api/vector_stores/${vectorStoreId}/files`, {
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || "Failed to fetch files")
      }

      const data = await response.json()
      this.displayVectorStoreFiles(data.files, modalEl)

    } catch (error) {
      console.error("Error fetching vector store files:", error)
      this.showFilesError(error.message, modalEl)
    }
  }

  /**
   * Show loading state for files
   */
  showFilesLoading(modalEl) {
    const loadingEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesLoading"]')
    const errorEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesError"]')
    const listEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesList"]')

    if (loadingEl) loadingEl.classList.remove("d-none")
    if (errorEl) errorEl.classList.add("d-none")
    if (listEl) listEl.innerHTML = ""
  }

  /**
   * Show error state for files
   */
  showFilesError(message, modalEl) {
    const loadingEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesLoading"]')
    const errorEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesError"]')
    const errorTextEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesErrorText"]')

    if (loadingEl) loadingEl.classList.add("d-none")
    if (errorEl) errorEl.classList.remove("d-none")
    if (errorTextEl) errorTextEl.textContent = message
  }

  /**
   * Display vector store files in the modal
   */
  displayVectorStoreFiles(files, modalEl) {
    const loadingEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesLoading"]')
    const listEl = modalEl.querySelector('[data-tools-config-target="vectorStoreFilesList"]')

    // Hide loading
    if (loadingEl) loadingEl.classList.add("d-none")

    if (!listEl) return

    if (files.length === 0) {
      listEl.innerHTML = `
        <div class="alert alert-info">
          <i class="bi bi-info-circle"></i>
          No files found in this vector store.
        </div>
      `
      return
    }

    // Build files table
    const filesHtml = `
      <div class="table-responsive">
        <table class="table table-sm table-hover">
          <thead>
            <tr>
              <th><i class="bi bi-file-earmark"></i> Filename</th>
              <th><i class="bi bi-hdd"></i> Size</th>
              <th><i class="bi bi-check-circle"></i> Status</th>
            </tr>
          </thead>
          <tbody>
            ${files.map(file => this.renderFileRow(file)).join('')}
          </tbody>
        </table>
      </div>
    `

    listEl.innerHTML = filesHtml
  }

  /**
   * Render a single file row
   */
  renderFileRow(file) {
    const statusBadge = this.getStatusBadge(file.status)
    const fileSize = this.formatFileSize(file.bytes)

    return `
      <tr>
        <td>
          <i class="bi bi-file-earmark-text text-primary me-1"></i>
          ${this.escapeHtml(file.filename)}
        </td>
        <td>${fileSize}</td>
        <td>${statusBadge}</td>
      </tr>
    `
  }

  /**
   * Get status badge HTML
   */
  getStatusBadge(status) {
    const statusMap = {
      'completed': '<span class="badge bg-success">Completed</span>',
      'in_progress': '<span class="badge bg-warning">In Progress</span>',
      'failed': '<span class="badge bg-danger">Failed</span>',
      'cancelled': '<span class="badge bg-secondary">Cancelled</span>'
    }
    return statusMap[status] || `<span class="badge bg-secondary">${status}</span>`
  }

  /**
   * Format file size in human-readable format
   */
  formatFileSize(bytes) {
    if (!bytes || bytes === 0) return '0 B'

    const units = ['B', 'KB', 'MB', 'GB']
    const k = 1024
    const i = Math.floor(Math.log(bytes) / Math.log(k))

    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${units[i]}`
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
