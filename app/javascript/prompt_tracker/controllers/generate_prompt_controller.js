import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

/**
 * GeneratePrompt Stimulus Controller
 * Handles AI-powered prompt generation from natural language descriptions
 */
export default class extends Controller {
  static targets = [
    "description",
    "generateButton"
  ]

  static values = {
    generateUrl: String
  }

  static outlets = ["playground"]

  connect() {
    console.log('[GeneratePromptController] connect() called')
    console.log('[GeneratePromptController] Element:', this.element)
    console.log('[GeneratePromptController] Has playground outlet?', this.hasPlaygroundOutlet)
    console.log('[GeneratePromptController] generateUrl value:', this.generateUrlValue)
    this.generatingModal = null

    // Attach event listener for the generate button in the modal
    // The modal gets moved to document.body by modal-fix, so we can't use data-action
    this.attachModalEventListeners()
  }

  /**
   * Attach event listeners for modal buttons that get moved outside controller scope
   */
  attachModalEventListeners() {
    const generateButton = document.getElementById('generatePromptButton')
    console.log('[GeneratePromptController] Looking for #generatePromptButton:', !!generateButton)
    if (generateButton) {
      generateButton.addEventListener('click', () => {
        console.log('[GeneratePromptController] Generate button clicked (via event listener)')
        this.submitGeneration()
      })
      console.log('[GeneratePromptController] Event listener attached to generate button')
    } else {
      console.error('[GeneratePromptController] #generatePromptButton not found!')
    }
  }

  /**
   * Open the generate prompt modal
   */
  openModal() {
    console.log('[GeneratePromptController] openModal() called')
    const modalEl = document.getElementById('generatePromptModal')
    console.log('[GeneratePromptController] Modal element found?', !!modalEl)
    if (modalEl) {
      const modal = new Modal(modalEl)
      modal.show()
      console.log('[GeneratePromptController] Modal shown')
    } else {
      console.error('[GeneratePromptController] Modal element #generatePromptModal not found!')
    }
  }

  /**
   * Submit generation request
   */
  async submitGeneration() {
    console.log('[GeneratePromptController] submitGeneration() called')
    const descriptionTextarea = document.getElementById('generateDescription')
    console.log('[GeneratePromptController] Description textarea found?', !!descriptionTextarea)

    if (!descriptionTextarea) {
      console.error('[GeneratePromptController] Description textarea not found!')
      return
    }

    const description = descriptionTextarea.value.trim()

    if (!description) {
      this.showAlert('Please describe what your prompt should do', 'warning')
      return
    }

    // Close the input modal
    const inputModalEl = document.getElementById('generatePromptModal')
    if (inputModalEl) {
      const inputModal = Modal.getInstance(inputModalEl)
      if (inputModal) inputModal.hide()
    }

    // Show generating modal
    this.showGeneratingModal()

    try {
      await this.generatePromptFromDescription(description)
    } catch (error) {
      console.error('Generation error:', error)
    } finally {
      this.hideGeneratingModal()
      if (descriptionTextarea) {
        descriptionTextarea.value = ''
      }
    }
  }

  /**
   * Generate prompt from description with animation
   */
  async generatePromptFromDescription(description) {
    try {
      const response = await fetch(this.generateUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ description })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || `Server error (${response.status})`)
      }

      const data = await response.json()

      if (data.success) {
        // Delegate to playground to insert the generated content
        if (this.hasPlaygroundOutlet) {
          await this.playgroundOutlet.insertGeneratedPrompts(data)
        }

        const message = data.explanation || 'Prompt generated successfully!'
        this.showAlert(message, 'success')
      } else {
        throw new Error(data.error || 'Generation failed')
      }
    } catch (error) {
      console.error('Generation error:', error)
      this.showAlert(`Generation failed: ${error.message}`, 'danger')
    }
  }

  showGeneratingModal() {
    const modalEl = document.getElementById('generatingModal')
    if (modalEl) {
      this.generatingModal = new Modal(modalEl)
      this.generatingModal.show()
    }
  }

  hideGeneratingModal() {
    if (this.generatingModal) {
      this.generatingModal.hide()
      this.generatingModal = null
    }
  }

  showAlert(message, type) {
    if (this.hasPlaygroundOutlet) {
      this.playgroundOutlet.showAlert(message, type)
    }
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
