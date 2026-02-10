import { Controller } from "@hotwired/stimulus"

/**
 * Playground Sync Stimulus Controller
 *
 * @description
 * Manages synchronization with remote entities (e.g., OpenAI Assistants) by fetching the latest
 * configuration from the remote API and updating the local prompt version. Only appears for APIs
 * with the :remote_entity_linked capability.
 *
 * @responsibilities
 * - Trigger manual sync with remote entity (OpenAI Assistant, etc.)
 * - Show loading state during sync operation
 * - Display sync errors with user-friendly messages
 * - Update last synced timestamp after successful sync
 * - Reload page after sync to show updated data
 *
 * @targets
 * - syncBtn: Manual sync button
 * - syncStatus: Sync status indicator
 * - lastSyncedAt: Last synced timestamp display
 * - syncError: Sync error message container
 *
 * @values
 * - syncUrl (String): Server endpoint for sync operation
 * - remoteEntityId (String): ID of remote entity (e.g., OpenAI Assistant ID)
 * - provider (String): Provider name (openai, anthropic, etc.)
 * - api (String): API name (assistants, etc.)
 *
 * @outlets
 * None - sync is independent operation
 *
 * @events_dispatched
 * None - sync triggers page reload on success
 *
 * @events_listened_to
 * - click (syncBtn): Trigger sync operation
 *
 * @communication_pattern
 * Independent controller that communicates directly with server. On successful sync, reloads
 * the page to show updated data. Does not interact with other playground controllers.
 *
 * @public_methods
 * None - all methods are internal
 *
 * @example
 * // In view (only shown for APIs with :remote_entity_linked capability):
 * <div data-controller="playground-sync"
 *      data-playground-sync-sync-url-value="/sync/:id"
 *      data-playground-sync-remote-entity-id-value="asst_123"
 *      data-playground-sync-provider-value="openai"
 *      data-playground-sync-api-value="assistants">
 *   <button data-playground-sync-target="syncBtn"
 *           data-action="click->playground-sync#syncRemoteEntity">Sync Now</button>
 * </div>
 */
export default class extends Controller {
  static targets = [
    "syncBtn",
    "syncStatus",
    "lastSyncedAt",
    "syncError"
  ]

  static values = {
    syncUrl: String,
    remoteEntityId: String,
    provider: String,
    api: String
  }

  connect() {
    console.log('[PlaygroundSyncController] ========== CONNECT ==========')
    console.log('[PlaygroundSyncController] Element:', this.element)
    console.log('[PlaygroundSyncController] Sync URL:', this.syncUrlValue)
    console.log('[PlaygroundSyncController] Remote Entity ID:', this.remoteEntityIdValue)
    console.log('[PlaygroundSyncController] Provider:', this.providerValue)
    console.log('[PlaygroundSyncController] API:', this.apiValue)
    console.log('[PlaygroundSyncController] ========== CONNECT COMPLETE ==========')
  }

  // Action: Sync with remote entity
  async syncRemoteEntity(event) {
    console.log('[PlaygroundSyncController] ========== SYNC REMOTE ENTITY ==========')
    event.preventDefault()

    if (!this.syncUrlValue) {
      console.error('[PlaygroundSyncController] No sync URL configured')
      this.showSyncError('Sync URL not configured')
      return
    }

    if (!this.remoteEntityIdValue) {
      console.error('[PlaygroundSyncController] No remote entity ID')
      this.showSyncError('No remote entity linked')
      return
    }

    console.log('[PlaygroundSyncController] Starting sync...')
    this.showSyncLoading(true)
    this.hideSyncError()

    try {
      const url = this.buildSyncUrl()
      console.log('[PlaygroundSyncController] Sync URL:', url)

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          remote_entity_id: this.remoteEntityIdValue,
          provider: this.providerValue,
          api: this.apiValue
        })
      })

      console.log('[PlaygroundSyncController] Response status:', response.status)

      if (!response.ok) {
        const text = await response.text()
        console.error('[PlaygroundSyncController] Server error response:', text)
        this.showSyncError(`Server error (${response.status}): ${response.statusText}`)
        this.showSyncLoading(false)
        return
      }

      const result = await response.json()
      console.log('[PlaygroundSyncController] Sync result:', result)

      if (result.success) {
        console.log('[PlaygroundSyncController] Sync successful!')

        // Update last synced timestamp
        if (this.hasLastSyncedAtTarget && result.synced_at) {
          this.lastSyncedAtTarget.textContent = result.synced_at
          console.log('[PlaygroundSyncController] Updated last synced at:', result.synced_at)
        }

        // Reload page to show updated data
        if (result.reload) {
          console.log('[PlaygroundSyncController] Reloading page...')
          setTimeout(() => {
            window.location.reload()
          }, 500)
        }
      } else {
        console.error('[PlaygroundSyncController] Sync failed:', result.errors)
        this.showSyncError(result.errors?.join(', ') || 'Sync failed')
      }

      this.showSyncLoading(false)
    } catch (error) {
      console.error('[PlaygroundSyncController] Network error:', error)
      this.showSyncError(`Network error: ${error.message}`)
      this.showSyncLoading(false)
    }

    console.log('[PlaygroundSyncController] ========== SYNC COMPLETE ==========')
  }

  // Build sync URL
  buildSyncUrl() {
    // Replace :id placeholder if present
    return this.syncUrlValue.replace(':id', this.remoteEntityIdValue)
  }

  // Show sync loading state
  showSyncLoading(isLoading) {
    console.log('[PlaygroundSyncController] Loading state:', isLoading)

    if (this.hasSyncBtnTarget) {
      this.syncBtnTarget.disabled = isLoading

      if (isLoading) {
        this.syncBtnTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Syncing...'
      } else {
        this.syncBtnTarget.innerHTML = '<i class="bi bi-arrow-repeat"></i> Sync from Remote'
      }
    }

    if (this.hasSyncStatusTarget) {
      if (isLoading) {
        this.syncStatusTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Syncing with remote entity...'
        this.syncStatusTarget.style.display = ''
      } else {
        this.syncStatusTarget.style.display = 'none'
      }
    }
  }

  // Show sync error
  showSyncError(message) {
    console.log('[PlaygroundSyncController] Showing sync error:', message)

    if (this.hasSyncErrorTarget) {
      this.syncErrorTarget.innerHTML = `
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
          <strong>Sync Error:</strong> ${message}
          <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>
      `
      this.syncErrorTarget.style.display = ''
    }
  }

  // Hide sync error
  hideSyncError() {
    console.log('[PlaygroundSyncController] Hiding sync error')

    if (this.hasSyncErrorTarget) {
      this.syncErrorTarget.style.display = 'none'
      this.syncErrorTarget.innerHTML = ''
    }
  }

  // Get CSRF token
  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
