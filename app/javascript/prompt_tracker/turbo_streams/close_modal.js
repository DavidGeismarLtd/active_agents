import * as bootstrap from "bootstrap"

/**
 * Custom Turbo Stream Action: close_modal
 *
 * Properly closes a Bootstrap modal by calling Bootstrap's hide() method.
 * This ensures proper cleanup of:
 * - Modal backdrop
 * - Body scroll lock
 * - Focus management
 * - Event listeners
 *
 * Unlike turbo_stream.remove(), this action:
 * 1. Keeps the modal in the DOM (so it can be reopened)
 * 2. Respects Bootstrap's modal lifecycle (hide.bs.modal → hidden.bs.modal)
 * 3. Properly removes the backdrop
 * 4. Restores body scroll state
 * 5. Handles multiple/nested modals correctly
 * 6. Fires Bootstrap events that other code may be listening to
 * 7. Resets the form inside the modal
 *
 * Usage in Rails controller:
 *   render turbo_stream: turbo_stream.action(:close_modal, "modal-id")
 */
Turbo.StreamActions.close_modal = function() {
  const modalId = this.getAttribute("target")
  const modalElement = document.getElementById(modalId)

  if (!modalElement) {
    console.warn(`[close_modal] Modal element with id "${modalId}" not found`)
    return
  }

  // Get or create Bootstrap Modal instance
  let bsModal = bootstrap.Modal.getInstance(modalElement)

  if (!bsModal) {
    // If no instance exists, create one
    bsModal = new bootstrap.Modal(modalElement)
  }

  // Reset any forms inside the modal
  const forms = modalElement.querySelectorAll('form')
  forms.forEach(form => form.reset())

  // Hide the modal using Bootstrap's API
  // This triggers the proper cleanup sequence:
  // 1. Fires 'hide.bs.modal' event
  // 2. Runs hide animation
  // 3. Removes backdrop
  // 4. Restores body scroll
  // 5. Fires 'hidden.bs.modal' event
  bsModal.hide()

  // Note: We do NOT remove the modal from the DOM
  // This allows it to be reopened without errors
}
