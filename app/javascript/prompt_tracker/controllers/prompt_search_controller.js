import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="prompt-search"
export default class extends Controller {
  static targets = ["item"]

  search(event) {
    const query = event.target.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      const promptName = item.dataset.promptName || ""
      const versionRows = item.querySelectorAll("[data-version-number]")
      
      if (query === "") {
        // Show all items when search is empty
        item.style.display = ""
        versionRows.forEach(row => row.style.display = "")
        return
      }

      // Check if prompt name matches
      const promptMatches = promptName.includes(query)
      
      // Check if any version number matches (e.g., searching for "2" shows v2)
      let anyVersionMatches = false
      versionRows.forEach(row => {
        const versionNumber = row.dataset.versionNumber || ""
        const versionMatches = versionNumber.includes(query) || `v${versionNumber}`.includes(query)
        
        if (versionMatches || promptMatches) {
          row.style.display = ""
          anyVersionMatches = true
        } else {
          row.style.display = "none"
        }
      })

      // Show/hide the entire accordion item based on matches
      if (promptMatches || anyVersionMatches) {
        item.style.display = ""
        
        // Auto-expand accordion if it has matches
        const collapseElement = item.querySelector(".accordion-collapse")
        if (collapseElement && !collapseElement.classList.contains("show")) {
          const button = item.querySelector(".accordion-button")
          if (button) {
            button.click()
          }
        }
      } else {
        item.style.display = "none"
      }
    })
  }
}

