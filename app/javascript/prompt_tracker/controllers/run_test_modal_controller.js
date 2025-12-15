import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeRadio", "datasetSection", "customSection", "datasetSelect", "rowCount", "submitButton"]

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
    }
  }

  showDatasetMode() {
    if (this.hasDatasetSectionTarget) {
      this.datasetSectionTarget.style.display = "block"
    }
    if (this.hasCustomSectionTarget) {
      this.customSectionTarget.style.display = "none"
    }
  }

  showCustomMode() {
    if (this.hasDatasetSectionTarget) {
      this.datasetSectionTarget.style.display = "none"
    }
    if (this.hasCustomSectionTarget) {
      this.customSectionTarget.style.display = "block"
    }
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

