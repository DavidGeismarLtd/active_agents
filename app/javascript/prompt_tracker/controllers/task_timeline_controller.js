import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

// Task Timeline Controller
// Handles expand/collapse functionality for iteration groups and event cards
export default class extends Controller {
  static targets = ["iterationGroup", "eventCard"]

  connect() {
    console.log("TaskTimelineController connected")
  }

  // Expand all iterations and event cards
  expandAll(event) {
    event.preventDefault()

    // Expand all iteration groups and event cards
    this.element.querySelectorAll('.collapse').forEach(collapse => {
      // Get or create Bootstrap Collapse instance
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

    // Collapse all iteration groups and event cards
    this.element.querySelectorAll('.collapse').forEach(collapse => {
      // Get or create Bootstrap Collapse instance
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
    // This method is here for potential custom logic
  }

  // Toggle a single event card
  toggleCard(event) {
    // Bootstrap handles the toggle automatically via data-bs-toggle
    // This method is here for potential custom logic
  }

  // Copy event data to clipboard
  copyToClipboard(event) {
    event.preventDefault()
    const button = event.currentTarget
    const dataElement = button.closest('.card-body').querySelector('pre code')

    if (dataElement) {
      const text = dataElement.textContent

      navigator.clipboard.writeText(text).then(() => {
        // Show success feedback
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
