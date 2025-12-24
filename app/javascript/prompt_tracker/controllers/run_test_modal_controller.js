import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeRadio", "datasetSection", "customSection", "datasetSelect", "rowCount", "submitButton", "form"]

  connect() {
    // Initialize the view based on the selected mode
    this.toggleMode()

    // If dataset select exists, update row count when changed
    if (this.hasDatasetSelectTarget) {
      this.datasetSelectTarget.addEventListener('change', this.updateRowCount.bind(this))
      this.updateRowCount()
    }
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

    const customInputs = this.customSectionTarget.querySelectorAll('input[data-required="true"], textarea[data-required="true"]')
    customInputs.forEach(input => {
      if (enabled) {
        input.setAttribute('required', 'required')
      } else {
        input.removeAttribute('required')
      }
    })
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
}
