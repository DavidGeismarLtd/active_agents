import { Controller } from "@hotwired/stimulus"

/**
 * Playground Sync Stimulus Controller
 *
 * @description
 * Manages bidirectional synchronization with remote entities (e.g., OpenAI Assistants).
 * Provides Push (local → remote) and Pull (remote → local) operations.
 *
 * @responsibilities
 * - Push local changes to remote entity (OpenAI Assistant, etc.)
 * - Pull latest from remote entity and update local PromptVersion
 * - Show loading state during sync operations
 * - Display sync errors with user-friendly messages
 * - Reload page after pull to show updated data
 *
 * @targets
 * - pushBtn: Push to remote button
 * - pullBtn: Pull from remote button
 * - syncStatus: Sync status indicator
 * - lastSyncedAt: Last synced timestamp display
 * - syncError: Sync error message container
 *
 * @values
 * - pushUrl (String): Server endpoint for push operation
 * - pullUrl (String): Server endpoint for pull operation
 * - remoteEntityId (String): ID of remote entity (e.g., OpenAI Assistant ID)
 * - provider (String): Provider name (openai, anthropic, etc.)
 * - api (String): API name (assistants, etc.)
 *
 * @outlets
 * - playground-prompt-editor: For collecting current form data during push
 * - playground-model-config: For collecting model config during push
 *
 * @events_dispatched
 * None - sync triggers page reload on success (for pull)
 *
 * @events_listened_to
 * - click (pushBtn): Trigger push operation
 * - click (pullBtn): Trigger pull operation
 *
 * @communication_pattern
 * Independent controller that communicates directly with server. On successful pull, reloads
 * the page to show updated data. Push updates sync status without reload.
 *
 * @public_methods
 * - pushToRemote(): Push local changes to remote entity
 * - pullFromRemote(): Pull latest from remote entity
 *
 * @example
 * // In view (only shown for APIs with :remote_entity_linked capability):
 * <div data-controller="playground-sync"
 *      data-playground-sync-push-url-value="/push_to_remote"
 *      data-playground-sync-pull-url-value="/pull_from_remote"
 *      data-playground-sync-remote-entity-id-value="asst_123">
 *   <button data-playground-sync-target="pushBtn"
 *           data-action="click->playground-sync#pushToRemote">Push</button>
 *   <button data-playground-sync-target="pullBtn"
 *           data-action="click->playground-sync#pullFromRemote">Pull</button>
 * </div>
 */
export default class extends Controller {
  static targets = [
    "pushBtn",
    "pullBtn",
    "syncStatus",
    "lastSyncedAt",
    "syncError"
  ]

  static values = {
    pushUrl: String,
    pullUrl: String,
    remoteEntityId: String,
    provider: String,
    api: String
  }

  static outlets = [
    "playground-prompt-editor",
    "playground-model-config"
  ]

  connect() {
    console.log('[PlaygroundSyncController] Connected')
    console.log('[PlaygroundSyncController] Push URL:', this.pushUrlValue)
    console.log('[PlaygroundSyncController] Pull URL:', this.pullUrlValue)
    console.log('[PlaygroundSyncController] Remote Entity ID:', this.remoteEntityIdValue)
  }

  // Action: Push local changes to remote entity
  async pushToRemote(event) {
    console.log('[PlaygroundSyncController] ========== PUSH TO REMOTE ==========')
    event.preventDefault()

    if (!this.pushUrlValue) {
      console.error('[PlaygroundSyncController] No push URL configured')
      this.showSyncError('Push URL not configured')
      return
    }

    console.log('[PlaygroundSyncController] Starting push...')
    this.showPushLoading(true)
    this.hideSyncError()

    try {
      // Collect current form data
      const formData = this.collectFormData()
      console.log('[PlaygroundSyncController] Form data:', formData)

      const response = await fetch(this.pushUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify(formData)
      })

      console.log('[PlaygroundSyncController] Response status:', response.status)

      if (!response.ok) {
        const text = await response.text()
        console.error('[PlaygroundSyncController] Server error response:', text)
        this.showSyncError(`Server error (${response.status}): ${response.statusText}`)
        this.showPushLoading(false)
        return
      }

      const result = await response.json()
      console.log('[PlaygroundSyncController] Push result:', result)

      if (result.success) {
        console.log('[PlaygroundSyncController] Push successful!')
        this.showPushSuccess()

        // Update last synced timestamp
        if (this.hasLastSyncedAtTarget && result.synced_at) {
          this.lastSyncedAtTarget.textContent = result.synced_at
        }
      } else {
        console.error('[PlaygroundSyncController] Push failed:', result.error)
        this.showSyncError(result.error || 'Push failed')
      }

      this.showPushLoading(false)
    } catch (error) {
      console.error('[PlaygroundSyncController] Network error:', error)
      this.showSyncError(`Network error: ${error.message}`)
      this.showPushLoading(false)
    }

    console.log('[PlaygroundSyncController] ========== PUSH COMPLETE ==========')
  }

  // Action: Pull latest from remote entity
  async pullFromRemote(event) {
    console.log('[PlaygroundSyncController] ========== PULL FROM REMOTE ==========')
    event.preventDefault()

    if (!this.pullUrlValue) {
      console.error('[PlaygroundSyncController] No pull URL configured')
      this.showSyncError('Pull URL not configured')
      return
    }

    if (!this.remoteEntityIdValue) {
      console.error('[PlaygroundSyncController] No remote entity ID')
      this.showSyncError('No remote entity linked')
      return
    }

    // Confirm before pulling (will overwrite local changes)
    if (!confirm('This will overwrite your local changes with the remote version. Continue?')) {
      return
    }

    console.log('[PlaygroundSyncController] Starting pull...')
    this.showPullLoading(true)
    this.hideSyncError()

    try {
      const response = await fetch(this.pullUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          remote_entity_id: this.remoteEntityIdValue
        })
      })

      console.log('[PlaygroundSyncController] Response status:', response.status)

      if (!response.ok) {
        const text = await response.text()
        console.error('[PlaygroundSyncController] Server error response:', text)
        this.showSyncError(`Server error (${response.status}): ${response.statusText}`)
        this.showPullLoading(false)
        return
      }

      const result = await response.json()
      console.log('[PlaygroundSyncController] Pull result:', result)

      if (result.success) {
        console.log('[PlaygroundSyncController] Pull successful!')

        // Reload page to show updated data
        if (result.reload) {
          console.log('[PlaygroundSyncController] Reloading page...')
          setTimeout(() => {
            window.location.reload()
          }, 500)
        }
      } else {
        console.error('[PlaygroundSyncController] Pull failed:', result.error)
        this.showSyncError(result.error || 'Pull failed')
      }

      this.showPullLoading(false)
    } catch (error) {
      console.error('[PlaygroundSyncController] Network error:', error)
      this.showSyncError(`Network error: ${error.message}`)
      this.showPullLoading(false)
    }

    console.log('[PlaygroundSyncController] ========== PULL COMPLETE ==========')
  }

  // Collect form data from outlets
  collectFormData() {
    const data = {}

    // Get prompts from editor outlet
    if (this.hasPlaygroundPromptEditorOutlet) {
      const editor = this.playgroundPromptEditorOutlet
      data.system_prompt = editor.getSystemPrompt?.() || ''
      data.user_prompt = editor.getUserPrompt?.() || ''
    }

    // Get model config from model-config outlet
    if (this.hasPlaygroundModelConfigOutlet) {
      const modelConfig = this.playgroundModelConfigOutlet
      data.model_config = modelConfig.getModelConfig?.() || {}
    }

    return data
  }

  // Show push loading state
  showPushLoading(isLoading) {
    if (this.hasPushBtnTarget) {
      this.pushBtnTarget.disabled = isLoading

      if (isLoading) {
        this.pushBtnTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Pushing...'
      } else {
        this.pushBtnTarget.innerHTML = '<i class="bi bi-cloud-arrow-up"></i> Push'
      }
    }

    if (this.hasSyncStatusTarget) {
      if (isLoading) {
        this.syncStatusTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Pushing to remote...'
        this.syncStatusTarget.style.display = ''
      } else {
        this.syncStatusTarget.style.display = 'none'
      }
    }
  }

  // Show push success state
  showPushSuccess() {
    if (this.hasPushBtnTarget) {
      this.pushBtnTarget.innerHTML = '<i class="bi bi-check-circle"></i> Pushed!'
      setTimeout(() => {
        this.pushBtnTarget.innerHTML = '<i class="bi bi-cloud-arrow-up"></i> Push'
      }, 2000)
    }
  }

  // Show pull loading state
  showPullLoading(isLoading) {
    if (this.hasPullBtnTarget) {
      this.pullBtnTarget.disabled = isLoading

      if (isLoading) {
        this.pullBtnTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Pulling...'
      } else {
        this.pullBtnTarget.innerHTML = '<i class="bi bi-cloud-arrow-down"></i> Pull'
      }
    }

    if (this.hasSyncStatusTarget) {
      if (isLoading) {
        this.syncStatusTarget.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Pulling from remote...'
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
        <div class="alert alert-danger alert-dismissible fade show mt-2" role="alert">
          <strong>Sync Error:</strong> ${message}
          <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>
      `
      this.syncErrorTarget.style.display = ''
    }
  }

  // Hide sync error
  hideSyncError() {
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
