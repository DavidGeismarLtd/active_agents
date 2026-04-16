import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

// Task Timeline Controller
// Handles expand/collapse, search/filter for iteration groups and event cards
export default class extends Controller {
  static targets = ["iterationGroup", "eventCard", "searchInput", "clearButton"]

  connect() {
    console.log("TaskTimelineController connected")
  }

  // Expand all iterations and event cards
  expandAll(event) {
    event.preventDefault()
    this.element.querySelectorAll('.collapse').forEach(collapse => {
      let bsCollapse = bootstrap.Collapse.getInstance(collapse)
      if (!bsCollapse) {
        bsCollapse = new bootstrap.Collapse(collapse, { toggle: false })
      }
      bsCollapse.show()
    })
  }

  // Collapse all iterations and event cards
  collapseAll(event) {
    event.preventDefault()
    this.element.querySelectorAll('.collapse').forEach(collapse => {
      let bsCollapse = bootstrap.Collapse.getInstance(collapse)
      if (!bsCollapse) {
        bsCollapse = new bootstrap.Collapse(collapse, { toggle: false })
      }
      bsCollapse.hide()
    })
  }

  // Toggle a single iteration
  toggleIteration(event) {
    // Bootstrap handles the toggle automatically via data-bs-toggle
  }

  // Toggle a single event card
  toggleCard(event) {
    // Bootstrap handles the toggle automatically via data-bs-toggle
  }

  // Search/filter timeline events by text
  search() {
    const query = this.searchInputTarget.value.trim().toLowerCase()

    // Show/hide clear button
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.style.display = query ? "block" : "none"
    }

    if (!query) {
      this._showAll()
      return
    }

    // Filter iteration groups
    this.iterationGroupTargets.forEach(group => {
      const timelineItems = group.querySelectorAll('.timeline-item')
      let groupHasMatch = false

      timelineItems.forEach(item => {
        const text = item.textContent.toLowerCase()
        const matches = text.includes(query)
        item.style.display = matches ? "" : "none"
        if (matches) groupHasMatch = true
      })

      // Show/hide the entire iteration group
      group.style.display = groupHasMatch ? "" : "none"

      // If group has matches, expand it
      if (groupHasMatch) {
        const collapse = group.querySelector('.collapse')
        if (collapse) {
          let bsCollapse = bootstrap.Collapse.getInstance(collapse)
          if (!bsCollapse) {
            bsCollapse = new bootstrap.Collapse(collapse, { toggle: false })
          }
          bsCollapse.show()
        }
      }
    })
  }

  // Clear search and show all events
  clearSearch() {
    this.searchInputTarget.value = ""
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.style.display = "none"
    }
    this._showAll()
  }

  // Show all iteration groups and timeline items
  _showAll() {
    this.iterationGroupTargets.forEach(group => {
      group.style.display = ""
      group.querySelectorAll('.timeline-item').forEach(item => {
        item.style.display = ""
      })
    })
  }

  // Copy event data to clipboard
  copyToClipboard(event) {
    event.preventDefault()
    const button = event.currentTarget
    const dataElement = button.closest('.card-body').querySelector('pre code')

    if (dataElement) {
      const text = dataElement.textContent

      navigator.clipboard.writeText(text).then(() => {
        const originalHTML = button.innerHTML
        button.innerHTML = '<i class="bi bi-check"></i> Copied!'
        button.classList.remove('btn-outline-secondary')
        button.classList.add('btn-success')

        setTimeout(() => {
          button.innerHTML = originalHTML
          button.classList.remove('btn-success')
          button.classList.add('btn-outline-secondary')
        }, 2000)
      }).catch(err => {
        console.error('Failed to copy:', err)
        alert('Failed to copy to clipboard')
      })
    }
  }
}
