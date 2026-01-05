import { Controller } from "@hotwired/stimulus"
import { Modal, Toast } from "bootstrap"

/**
 * File Management Stimulus Controller
 * Handles file uploads and vector store management for OpenAI Assistants
 */
export default class extends Controller {
  static targets = [
    "fileInput",
    "uploadButton",
    "uploadProgress",
    "filesList",
    "refreshButton",
    "vectorStoreSelect",
    "attachButton",
    "vectorStoreInfo",
    "vectorStoreName"
    // Note: newVectorStoreName and modalFilesList are accessed by ID
    // because the modal is moved outside this controller's scope by modal-fix
  ]

  static values = {
    assistantId: String,
    uploadUrl: String,
    listFilesUrl: String,
    deleteFileUrl: String,
    createVectorStoreUrl: String,
    listVectorStoresUrl: String,
    attachVectorStoreUrl: String,
    addFileToVectorStoreUrl: String,
    currentVectorStoreIds: Array,
    isNew: Boolean
  }

  connect() {
    console.log("File Management controller connected")

    if (!this.isNewValue) {
      this.loadFiles()
      this.loadVectorStores()
      this.updateVectorStoreInfo()
    }

    this.selectedFiles = []

    // Bind global click handler for modal buttons that are moved outside controller scope
    this.boundCreateVectorStoreHandler = this.handleCreateVectorStoreClick.bind(this)
    document.addEventListener("click", this.boundCreateVectorStoreHandler)
  }

  disconnect() {
    // Clean up global event listener
    if (this.boundCreateVectorStoreHandler) {
      document.removeEventListener("click", this.boundCreateVectorStoreHandler)
    }
  }

  handleCreateVectorStoreClick(event) {
    // Check if the clicked element or its parent has the create vector store action
    const button = event.target.closest('[data-action*="file-management#createVectorStore"]')
    if (button) {
      event.preventDefault()
      this.createVectorStore()
    }
  }

  // ========================================
  // File Upload
  // ========================================

  triggerFileInput() {
    this.fileInputTarget.click()
  }

  async uploadFile(event) {
    const files = event.target.files
    if (!files || files.length === 0) return

    this.showUploadProgress()

    for (const file of files) {
      await this.uploadSingleFile(file)
    }

    this.hideUploadProgress()
    this.fileInputTarget.value = ""
    this.loadFiles()
  }

  async uploadSingleFile(file) {
    const formData = new FormData()
    formData.append("file", file)

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: formData
      })

      const data = await response.json()

      if (!data.success) {
        this.showToast(`Failed to upload ${file.name}: ${data.error}`, "error")
      } else {
        this.showToast(`Uploaded ${file.name}`, "success")
      }
    } catch (error) {
      console.error("Upload error:", error)
      this.showToast(`Error uploading ${file.name}`, "error")
    }
  }

  showUploadProgress() {
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.style.display = "block"
    }
  }

  hideUploadProgress() {
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.style.display = "none"
    }
  }

  // ========================================
  // File List
  // ========================================

  async loadFiles() {
    if (this.hasRefreshButtonTarget) {
      this.refreshButtonTarget.disabled = true
    }

    try {
      const response = await fetch(this.listFilesUrlValue, {
        headers: {
          "X-CSRF-Token": this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success) {
        this.renderFilesList(data.files)
      } else {
        this.filesListTarget.innerHTML = `
          <div class="text-danger small text-center py-2">
            <i class="bi bi-exclamation-triangle"></i> ${data.error}
          </div>
        `
      }
    } catch (error) {
      console.error("Error loading files:", error)
      this.filesListTarget.innerHTML = `
        <div class="text-danger small text-center py-2">
          <i class="bi bi-exclamation-triangle"></i> Failed to load files
        </div>
      `
    } finally {
      if (this.hasRefreshButtonTarget) {
        this.refreshButtonTarget.disabled = false
      }
    }
  }

  refreshFiles() {
    this.loadFiles()
  }

  renderFilesList(files) {
    if (!files || files.length === 0) {
      this.filesListTarget.innerHTML = `
        <div class="text-muted small text-center py-2">
          <i class="bi bi-folder2-open"></i> No files uploaded yet
        </div>
      `
      return
    }

    this.files = files
    const html = files.map(file => this.renderFileItem(file)).join("")
    this.filesListTarget.innerHTML = html
  }

  renderFileItem(file) {
    const sizeKb = Math.round((file.bytes || 0) / 1024)

    return `
      <div class="file-item d-flex justify-content-between align-items-center py-1 px-2 border-bottom" data-file-id="${file.id}">
        <div class="file-info">
          <i class="bi bi-file-earmark-text text-primary"></i>
          <span class="small ms-1" title="${file.filename}">${this.truncateFilename(file.filename, 25)}</span>
          <span class="text-muted small ms-2">${sizeKb} KB</span>
        </div>
        <button class="btn btn-sm btn-outline-danger py-0 px-1"
                data-action="click->file-management#deleteFile"
                data-file-id="${file.id}"
                title="Delete file">
          <i class="bi bi-trash"></i>
        </button>
      </div>
    `
  }

  truncateFilename(filename, maxLength) {
    if (!filename || filename.length <= maxLength) return filename
    const ext = filename.split(".").pop()
    const nameWithoutExt = filename.slice(0, -(ext.length + 1))
    const truncatedName = nameWithoutExt.slice(0, maxLength - ext.length - 4) + "..."
    return truncatedName + "." + ext
  }

  async deleteFile(event) {
    const fileId = event.currentTarget.dataset.fileId
    if (!confirm("Are you sure you want to delete this file?")) return

    try {
      const response = await fetch(`${this.deleteFileUrlValue}?file_id=${fileId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success) {
        this.showToast("File deleted", "success")
        this.loadFiles()
      } else {
        this.showToast(`Failed to delete: ${data.error}`, "error")
      }
    } catch (error) {
      console.error("Delete error:", error)
      this.showToast("Error deleting file", "error")
    }
  }

  // ========================================
  // Vector Stores
  // ========================================

  async loadVectorStores() {
    try {
      const response = await fetch(this.listVectorStoresUrlValue, {
        headers: {
          "X-CSRF-Token": this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success) {
        this.renderVectorStoreOptions(data.vector_stores)
      }
    } catch (error) {
      console.error("Error loading vector stores:", error)
    }
  }

  renderVectorStoreOptions(vectorStores) {
    this.vectorStores = vectorStores || []

    let options = '<option value="">-- Select or create --</option>'
    options += '<option value="__new__">+ Create new vector store...</option>'

    const currentIds = this.currentVectorStoreIdsValue || []

    vectorStores.forEach(vs => {
      const selected = currentIds.includes(vs.id) ? "selected" : ""
      options += `<option value="${vs.id}" ${selected}>${vs.name || vs.id}</option>`
    })

    if (this.hasVectorStoreSelectTarget) {
      this.vectorStoreSelectTarget.innerHTML = options

      // Explicitly set the select value after updating innerHTML
      // (the selected attribute alone doesn't always work for dynamic updates)
      if (currentIds.length > 0) {
        const targetId = currentIds[0]
        // Only set value if the option exists in the list
        const optionExists = vectorStores.some(vs => vs.id === targetId)
        if (optionExists) {
          this.vectorStoreSelectTarget.value = targetId
        }
      }
    }
  }

  onVectorStoreChange(event) {
    const value = event.target.value

    if (value === "__new__") {
      this.showNewVectorStoreModal()
      event.target.value = ""
      return
    }

    if (this.hasAttachButtonTarget) {
      this.attachButtonTarget.disabled = !value
    }
  }

  updateVectorStoreInfo() {
    if (this.currentVectorStoreIdsValue.length > 0) {
      if (this.hasVectorStoreInfoTarget) {
        this.vectorStoreInfoTarget.style.display = "block"
        if (this.hasVectorStoreNameTarget) {
          this.vectorStoreNameTarget.textContent = `${this.currentVectorStoreIdsValue.length} vector store(s) attached`
        }
      }
    } else {
      if (this.hasVectorStoreInfoTarget) {
        this.vectorStoreInfoTarget.style.display = "none"
      }
    }
  }

  showNewVectorStoreModal() {
    // Populate modal files list (find by ID since modal is moved outside controller scope)
    const modalFilesList = document.getElementById("newVectorStoreModalFilesList")
    if (modalFilesList && this.files) {
      const html = this.files.map(file => `
        <div class="form-check">
          <input class="form-check-input" type="checkbox" value="${file.id}" id="modal_file_${file.id}">
          <label class="form-check-label" for="modal_file_${file.id}">
            ${file.filename}
          </label>
        </div>
      `).join("")
      modalFilesList.innerHTML = html || '<div class="text-muted small">No files available</div>'
    }

    const modal = new Modal(document.getElementById("newVectorStoreModal"))
    modal.show()
  }

  async createVectorStore() {
    // Find by ID since modal is moved outside controller scope by modal-fix
    const nameInput = document.getElementById("newVectorStoreNameInput")
    const name = nameInput ? nameInput.value : "Knowledge Base"

    // Get selected file IDs from modal
    const fileIds = []
    const modalFilesList = document.getElementById("newVectorStoreModalFilesList")
    if (modalFilesList) {
      modalFilesList.querySelectorAll("input:checked").forEach(input => {
        fileIds.push(input.value)
      })
    }

    try {
      const response = await fetch(this.createVectorStoreUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({ name, file_ids: fileIds })
      })

      const data = await response.json()

      if (data.success) {
        // Close modal
        const modal = Modal.getInstance(document.getElementById("newVectorStoreModal"))
        if (modal) modal.hide()

        // Attach the new vector store
        await this.attachVectorStoreById(data.vector_store.id)

        this.showToast("Vector store created and attached", "success")

        // Reload vector stores and wait for it to complete
        await this.loadVectorStores()
      } else {
        this.showToast(`Failed: ${data.error}`, "error")
      }
    } catch (error) {
      console.error("Create vector store error:", error)
      this.showToast("Error creating vector store", "error")
    }
  }

  async attachVectorStore() {
    const vectorStoreId = this.vectorStoreSelectTarget.value
    if (!vectorStoreId || vectorStoreId === "__new__") return

    await this.attachVectorStoreById(vectorStoreId)
  }

  async attachVectorStoreById(vectorStoreId) {
    try {
      const response = await fetch(this.attachVectorStoreUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({ vector_store_ids: [vectorStoreId] })
      })

      const data = await response.json()

      if (data.success) {
        this.currentVectorStoreIdsValue = [vectorStoreId]
        this.updateVectorStoreInfo()
        this.showToast("Vector store attached", "success")
      } else {
        this.showToast(`Failed: ${data.error}`, "error")
      }
    } catch (error) {
      console.error("Attach error:", error)
      this.showToast("Error attaching vector store", "error")
    }
  }

  async detachVectorStore() {
    try {
      const response = await fetch(this.attachVectorStoreUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({ vector_store_ids: [] })
      })

      const data = await response.json()

      if (data.success) {
        this.currentVectorStoreIdsValue = []
        this.updateVectorStoreInfo()
        this.vectorStoreSelectTarget.value = ""
        this.showToast("Vector store detached", "success")
      } else {
        this.showToast(`Failed: ${data.error}`, "error")
      }
    } catch (error) {
      console.error("Detach error:", error)
      this.showToast("Error detaching vector store", "error")
    }
  }

  // ========================================
  // Utilities
  // ========================================

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  showToast(message, type = "info") {
    // Try to use the playground toast if available
    const toastEl = document.querySelector('[data-assistant-playground-target="toast"]')
    const toastBody = document.querySelector('[data-assistant-playground-target="toastBody"]')

    if (toastEl && toastBody) {
      toastBody.textContent = message
      toastEl.classList.remove("bg-success", "bg-danger", "text-white")

      if (type === "success") {
        toastEl.classList.add("bg-success", "text-white")
      } else if (type === "error") {
        toastEl.classList.add("bg-danger", "text-white")
      }

      const bsToast = new Toast(toastEl)
      bsToast.show()
    } else {
      // Fallback to console
      console.log(`[${type}] ${message}`)
    }
  }
}
