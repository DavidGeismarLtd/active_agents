import { Controller } from "@hotwired/stimulus"

/**
 * Modal Fix Stimulus Controller
 *
 * Fixes Bootstrap modal z-index issues by ensuring modals appear above backdrops.
 * Bootstrap creates backdrop AFTER modal in DOM, which can cause z-index conflicts.
 *
 * Solution: Move modals to end of body and ensure proper DOM ordering.
 */
export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this.moveModalsToBody()
    this.attachModalListeners()
  }

  /**
   * Move all modal targets to the end of document.body
   * This ensures they are rendered after any backdrops
   */
  moveModalsToBody() {
    this.modalTargets.forEach(modal => {
      if (!modal.hasAttribute('data-moved')) {
        document.body.appendChild(modal)
        modal.setAttribute('data-moved', 'true')
      }
    })
  }

  /**
   * Attach event listeners to ensure modals stay on top
   */
  attachModalListeners() {
    this.modalTargets.forEach(modal => {
      this.ensureModalOnTop(modal)
    })
  }

  /**
   * Ensure a modal appears above its backdrop
   * @param {HTMLElement} modalElement - The modal element
   */
  ensureModalOnTop(modalElement) {
    if (!modalElement) return

    // When modal starts to show
    modalElement.addEventListener('show.bs.modal', (e) => {
      // Move modal to end of body again (in case backdrop was added)
      document.body.appendChild(modalElement)
    })

    // After modal is shown
    modalElement.addEventListener('shown.bs.modal', (e) => {
      // Ensure modal is after backdrop in DOM
      const backdrops = document.querySelectorAll('.modal-backdrop')
      if (backdrops.length > 0) {
        // Move modal after the last backdrop
        const lastBackdrop = backdrops[backdrops.length - 1]
        lastBackdrop.parentNode.insertBefore(modalElement, lastBackdrop.nextSibling)
      }
    })
  }
}
