import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Playground File Search Controller
 *
 * Single Responsibility: Manage file search tool configuration (vector stores)
 *
 * This controller handles:
 * - Loading available vector stores from API
 * - Adding/removing vector stores from configuration
 * - Creating new vector stores with file uploads
 * - Viewing files in a vector store
 * - Enforcing 2-vector-store limit (OpenAI Responses API hard limit)
 *
 * @fires playground-file-search:configChanged - When vector store config changes
 */
export default class extends Controller {
  static targets = [
    "vectorStoreSelect",
    "selectedVectorStores",
    "vectorStoreCount",
    "vectorStoreAddButton",
    "vectorStoreError",
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
      this.updateVectorStoreCount()
      this.checkVectorStoreLimit()
    })
  }

  /**
   * Load available vector stores from the API
   * @param {Event} event - Optional click event
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
    badge.dataset.action = "click->playground-file-search#showVectorStoreFiles"
    badge.title = "Click to view files"
    badge.innerHTML = `
      <span class="vector-store-name">${this.escapeHtml(storeName)}</span>
      <button type="button" class="btn-close btn-close-white" style="font-size: 0.6rem;"
              data-action="click->playground-file-search#removeVectorStore"
              onclick="event.stopPropagation()"></button>
    `

    this.selectedVectorStoresTarget.appendChild(badge)

    // Remove the option from the select to prevent duplicate additions
    selectedOption.remove()
    select.value = ""

    this.updateVectorStoreCount()
    this.updateAddButtonState()
    this.dispatchConfigChange()
  }

  /**
   * Remove a vector store from the selection
   * @param {Event} event - Click event from remove button
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
    this.dispatchConfigChange()
  }

  /**
   * Show the create vector store modal
   */
  showCreateVectorStoreModal() {
    console.log("[playground-file-search] showCreateVectorStoreModal called")
    console.log("[playground-file-search] hasCreateVectorStoreModalTarget:", this.hasCreateVectorStoreModalTarget)

    if (!this.hasCreateVectorStoreModalTarget) {
      console.error("[playground-file-search] createVectorStoreModal target not found!")
      return
    }

    const modalEl = this.createVectorStoreModalTarget
    console.log("[playground-file-search] Modal element found:", modalEl)

    // Move modal to end of body to fix z-index issues with backdrop
    if (!modalEl.hasAttribute("data-moved-to-body")) {
      document.body.appendChild(modalEl)
      modalEl.setAttribute("data-moved-to-body", "true")
      console.log("[playground-file-search] Modal moved to body")
    }

    // Reset form
    if (this.hasVectorStoreNameTarget) this.vectorStoreNameTarget.value = ""
    if (this.hasVectorStoreFilesTarget) this.vectorStoreFilesTarget.value = ""
    if (this.hasCreateVectorStoreStatusTarget) this.createVectorStoreStatusTarget.classList.add("d-none")
    if (this.hasCreateVectorStoreErrorTarget) this.createVectorStoreErrorTarget.classList.add("d-none")
    if (this.hasCreateVectorStoreButtonTarget) this.createVectorStoreButtonTarget.disabled = false

    const modal = new Modal(modalEl)
    console.log("[playground-file-search] Showing modal...")
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
      badge.dataset.action = "click->playground-file-search#showVectorStoreFiles"
      badge.title = "Click to view files"
      badge.innerHTML = `
        <span class="vector-store-name">${this.escapeHtml(data.name)}</span>
        <button type="button" class="btn-close btn-close-white" style="font-size: 0.6rem;"
                data-action="click->playground-file-search#removeVectorStore"
                onclick="event.stopPropagation()"></button>
      `
      this.selectedVectorStoresTarget.appendChild(badge)

      // Close modal after short delay
      setTimeout(() => {
        Modal.getInstance(this.createVectorStoreModalTarget)?.hide()
      }, 500)

      this.updateVectorStoreCount()
      this.updateAddButtonState()
      this.dispatchConfigChange()

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
   * @param {string} message - Error message to display
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
   * @returns {number} Number of selected vector stores
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
   * @param {string} message - Error message to display
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
   * Show modal with files in a vector store
   * @param {Event} event - Click event from vector store badge
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
    const titleEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesModalTitle"]')
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
   * @param {HTMLElement} modalEl - Modal element
   */
  showFilesLoading(modalEl) {
    const loadingEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesLoading"]')
    const errorEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesError"]')
    const listEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesList"]')

    if (loadingEl) loadingEl.classList.remove("d-none")
    if (errorEl) errorEl.classList.add("d-none")
    if (listEl) listEl.innerHTML = ""
  }

  /**
   * Show error state for files
   * @param {string} message - Error message
   * @param {HTMLElement} modalEl - Modal element
   */
  showFilesError(message, modalEl) {
    const loadingEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesLoading"]')
    const errorEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesError"]')
    const errorTextEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesErrorText"]')

    if (loadingEl) loadingEl.classList.add("d-none")
    if (errorEl) errorEl.classList.remove("d-none")
    if (errorTextEl) errorTextEl.textContent = message
  }

  /**
   * Display vector store files in the modal
   * @param {Array} files - Array of file objects
   * @param {HTMLElement} modalEl - Modal element
   */
  displayVectorStoreFiles(files, modalEl) {
    const loadingEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesLoading"]')
    const listEl = modalEl.querySelector('[data-playground-file-search-target="vectorStoreFilesList"]')

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
   * @param {Object} file - File object
   * @returns {string} HTML string for file row
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
   * @param {string} status - File status
   * @returns {string} HTML string for status badge
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
   * @param {number} bytes - File size in bytes
   * @returns {string} Formatted file size
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
   * @param {string} text - Text to escape
   * @returns {string} Escaped HTML
   */
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Get current vector store configuration
   * @returns {Object} Vector store configuration
   */
  getVectorStoreConfig() {
    const vectorStores = Array.from(
      this.selectedVectorStoresTarget.querySelectorAll("[data-vector-store-id]")
    ).map(badge => ({
      id: badge.dataset.vectorStoreId,
      name: badge.dataset.vectorStoreName
    }))

    return {
      vector_store_ids: vectorStores.map(vs => vs.id),
      vector_stores: vectorStores
    }
  }

  /**
   * Dispatch custom event when config changes
   * @private
   */
  dispatchConfigChange() {
    const config = this.getVectorStoreConfig()

    this.dispatch("configChanged", {
      detail: { config },
      prefix: "playground-file-search"
    })
  }
}
