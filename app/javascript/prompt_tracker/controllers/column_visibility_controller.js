import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "checkbox"]
  static values = {
    storageKey: { type: String, default: "testTableColumns" }
  }

  connect() {
    this.loadPreferences()
  }

  toggle(event) {
    const columnName = event.target.dataset.columnName
    const isVisible = event.target.checked

    this.setColumnVisibility(columnName, isVisible)
    this.savePreferences()
  }

  setColumnVisibility(columnName, isVisible) {
    // Find all elements with this column name (headers and cells)
    const elements = this.element.querySelectorAll(`[data-column="${columnName}"]`)

    elements.forEach(element => {
      if (isVisible) {
        element.classList.remove('d-none')
      } else {
        element.classList.add('d-none')
      }
    })
  }

  savePreferences() {
    const preferences = {}

    this.checkboxTargets.forEach(checkbox => {
      preferences[checkbox.dataset.columnName] = checkbox.checked
    })

    localStorage.setItem(this.storageKeyValue, JSON.stringify(preferences))
  }

  loadPreferences() {
    const saved = localStorage.getItem(this.storageKeyValue)

    if (!saved) return

    try {
      const preferences = JSON.parse(saved)

      Object.entries(preferences).forEach(([columnName, isVisible]) => {
        // Update checkbox state
        const checkbox = this.checkboxTargets.find(cb => cb.dataset.columnName === columnName)
        if (checkbox) {
          checkbox.checked = isVisible
        }

        // Update column visibility
        this.setColumnVisibility(columnName, isVisible)
      })
    } catch (e) {
      console.error('Failed to load column preferences:', e)
    }
  }

  showAll() {
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = true
      this.setColumnVisibility(checkbox.dataset.columnName, true)
    })
    this.savePreferences()
  }

  hideAll() {
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
      this.setColumnVisibility(checkbox.dataset.columnName, false)
    })
    this.savePreferences()
  }
}
