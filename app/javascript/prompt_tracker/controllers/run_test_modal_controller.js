import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
	static targets = [
		"modeRadio",
		"datasetSection",
		"customSection",
		"datasetSelect",
		"rowCount",
		"submitButton",
		"form",
		"executionModeRadio",
		"conversationSection"
	]

  connect() {
    // Initialize the view based on the selected mode
    this.toggleMode()

    // If dataset select exists, update row count when changed
    if (this.hasDatasetSelectTarget) {
      this.datasetSelectTarget.addEventListener('change', this.updateRowCount.bind(this))
      this.datasetSelectTarget.addEventListener('change', this.validateForm.bind(this))
      this.updateRowCount()
    }

    // Add validation listeners to custom fields
    if (this.hasCustomSectionTarget) {
      const customInputs = this.customSectionTarget.querySelectorAll('input, textarea')
      customInputs.forEach(input => {
        input.addEventListener('input', this.validateForm.bind(this))
      })

			// Initialize execution mode state (single vs conversational) for custom runs
			if (this.hasExecutionModeRadioTarget) {
				this.executionModeRadioTargets.forEach(radio => {
					radio.addEventListener('change', this.toggleExecutionMode.bind(this))
				})
				this.toggleExecutionMode()
			}
    }

    // Initial validation
    this.validateForm()
  }

  toggleMode() {
    const selectedMode = this.modeRadioTargets.find(radio => radio.checked)?.value

    if (selectedMode === "dataset") {
      this.showDatasetMode()
    } else if (selectedMode === "single") {
      this.showCustomMode()
    } else {
      // If no mode is selected, default to dataset mode and check the radio
      const datasetRadio = this.modeRadioTargets.find(radio => radio.value === "dataset")
      if (datasetRadio) {
        datasetRadio.checked = true
        this.showDatasetMode()
      }
    }

    // Validate after mode change
    this.validateForm()
  }

  showDatasetMode() {
    if (this.hasDatasetSectionTarget) {
      this.datasetSectionTarget.style.display = "block"
    }
    if (this.hasCustomSectionTarget) {
      this.customSectionTarget.style.display = "none"
    }
    // Enable dataset select validation, disable custom fields validation
    this.toggleDatasetSelectRequired(true)
    this.toggleCustomFieldsRequired(false)
  }

  showCustomMode() {
    if (this.hasDatasetSectionTarget) {
      this.datasetSectionTarget.style.display = "none"
    }
    if (this.hasCustomSectionTarget) {
      this.customSectionTarget.style.display = "block"
    }
    // Disable dataset select validation, enable custom fields validation
    this.toggleDatasetSelectRequired(false)
    this.toggleCustomFieldsRequired(true)
		this.toggleExecutionMode()
  }

  toggleDatasetSelectRequired(enabled) {
    if (!this.hasDatasetSelectTarget) return

    if (enabled) {
      this.datasetSelectTarget.setAttribute('required', 'required')
    } else {
      this.datasetSelectTarget.removeAttribute('required')
    }
  }

  toggleCustomFieldsRequired(enabled) {
    if (!this.hasCustomSectionTarget) return

		// Standard custom inputs (template variables etc.), excluding
		// conversation-specific fields which are managed separately.
		const selector = 'input[data-required="true"]:not([data-conversation-field="true"]), textarea[data-required="true"]:not([data-conversation-field="true"])'
		const customInputs = this.customSectionTarget.querySelectorAll(selector)
    customInputs.forEach(input => {
      if (enabled) {
        input.setAttribute('required', 'required')
      } else {
        input.removeAttribute('required')
      }
    })
  }

	toggleConversationFieldsRequired(enabled) {
		if (!this.hasCustomSectionTarget) return

		const selector = 'input[data-conversation-field="true"][data-required="true"], textarea[data-conversation-field="true"][data-required="true"]'
		const convoInputs = this.customSectionTarget.querySelectorAll(selector)
		convoInputs.forEach(input => {
			if (enabled) {
				input.setAttribute('required', 'required')
			} else {
				input.removeAttribute('required')
			}
		})
	}

	toggleExecutionMode() {
		// Only relevant when custom section is present/visible
		if (!this.hasCustomSectionTarget) return

		const selectedExecutionMode = this.hasExecutionModeRadioTarget
			? this.executionModeRadioTargets.find(radio => radio.checked)?.value
			: "single"

		const isConversational = selectedExecutionMode === "conversation"

		// Show/hide conversation settings section if present
		if (this.hasConversationSectionTarget) {
			this.conversationSectionTarget.style.display = isConversational ? "block" : "none"
		}

		// Manage requiredness of conversation-specific fields
		this.toggleConversationFieldsRequired(isConversational)

		// Re-run validation when execution mode changes
		this.validateForm()
	}

  updateRowCount() {
    if (!this.hasDatasetSelectTarget || !this.hasRowCountTarget) return

    const selectedOption = this.datasetSelectTarget.selectedOptions[0]
    if (selectedOption && selectedOption.value) {
      // Fetch dataset row count via AJAX
      const datasetId = selectedOption.value
      fetch(`/prompt_tracker/testing/datasets/${datasetId}/row_count`)
        .then(response => response.json())
        .then(data => {
          this.rowCountTarget.textContent = data.count
        })
        .catch(error => {
          console.error('Error fetching row count:', error)
          this.rowCountTarget.textContent = '?'
        })
    } else {
      this.rowCountTarget.textContent = '?'
    }
  }

  validateForm() {
    if (!this.hasSubmitButtonTarget) return

    const selectedMode = this.modeRadioTargets.find(radio => radio.checked)?.value
    let isValid = false

    if (selectedMode === "dataset") {
      // Dataset mode: require a dataset to be selected
      isValid = this.hasDatasetSelectTarget && this.datasetSelectTarget.value !== ""
    } else if (selectedMode === "single") {
      // Single mode: require all required custom fields to be filled
      if (this.hasCustomSectionTarget) {
        const requiredInputs = this.customSectionTarget.querySelectorAll('[required]')
        isValid = Array.from(requiredInputs).every(input => input.value.trim() !== "")
      }
    }

    this.submitButtonTarget.disabled = !isValid
  }
}
