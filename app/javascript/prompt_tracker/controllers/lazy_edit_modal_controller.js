import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * Lazy Edit Modal Controller
 *
 * Opens edit modal for dataset rows, lazy-loading the modal HTML if it doesn't exist yet.
 * This solves the issue where modals with forms get corrupted when broadcast via Turbo Streams
 * (form tags self-close inside <template> tags).
 *
 * Strategy:
 * - On initial page load: Modals are rendered normally (no corruption)
 * - On Turbo Stream broadcast: Modals are skipped (skip_modal: true)
 * - When Edit button clicked: Check if modal exists, if not fetch it via AJAX
 *
 * Usage:
 *   <button data-controller="lazy-edit-modal"
 *           data-lazy-edit-modal-row-id-value="123"
 *           data-lazy-edit-modal-index-value="1"
 *           data-lazy-edit-modal-update-path-value="/path/to/update"
 *           data-action="click->lazy-edit-modal#openOrLoad">
 *     Edit
 *   </button>
 */
export default class extends Controller {
  static values = {
    rowId: Number,
    index: Number,
    updatePath: String
  }

  /**
   * Open modal if it exists, otherwise load it first
   */
  openOrLoad(event) {
    event.preventDefault()

    const modalId = `editRowModal-${this.rowIdValue}`
    const modalElement = document.getElementById(modalId)

    if (modalElement) {
      // Modal already exists, just show it
      const modal = new Modal(modalElement)
      modal.show()
    } else {
      // Modal doesn't exist, fetch it via AJAX
      this.loadAndShowModal(modalId)
    }
  }

  /**
   * Fetch modal HTML and inject it into the DOM, then show it
   */
  loadAndShowModal(modalId) {
    // Fetch the modal HTML from the server
    // We'll add a new endpoint that returns just the modal HTML
    const url = `${this.updatePathValue}/edit_modal`

    fetch(url, {
      headers: {
        'Accept': 'text/html'
      }
    })
      .then(response => {
        if (!response.ok) {
          throw new Error('Failed to load modal')
        }
        return response.text()
      })
      .then(html => {
        // Inject the modal HTML into the body
        document.body.insertAdjacentHTML('beforeend', html)

        // Show the modal after a brief delay to ensure DOM is updated
        setTimeout(() => {
          const modalElement = document.getElementById(modalId)
          if (modalElement) {
            const modal = new Modal(modalElement)
            modal.show()
          }
        }, 50)
      })
      .catch(error => {
        console.error('Error loading modal:', error)
        alert('Failed to load edit form')
      })
  }
}
