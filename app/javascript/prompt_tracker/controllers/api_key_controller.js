import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="prompt-tracker--api-key"
export default class extends Controller {
  static targets = ["key", "toggleIcon", "copyButton"]

  connect() {
    console.log("=== API Key Controller Connected ===")
    console.log("Controller element:", this.element)
    console.log("Has key target:", this.hasKeyTarget)
    console.log("Has toggleIcon target:", this.hasToggleIconTarget)
    console.log("Has copyButton target:", this.hasCopyButtonTarget)

    if (this.hasKeyTarget) {
      console.log("Key input element:", this.keyTarget)
      console.log("Key value:", this.keyTarget.value)
    }

    this.isVisible = false
    console.log("=== End Connection Log ===")
  }

  toggle(event) {
    console.log("=== Toggle Method Called ===")
    console.log("Event:", event)
    console.log("Event target:", event.target)
    console.log("Current isVisible:", this.isVisible)

    this.isVisible = !this.isVisible
    console.log("New isVisible:", this.isVisible)

    if (this.isVisible) {
      console.log("Showing password...")
      this.keyTarget.type = "text"
      this.toggleIconTarget.classList.remove("bi-eye")
      this.toggleIconTarget.classList.add("bi-eye-slash")
    } else {
      console.log("Hiding password...")
      this.keyTarget.type = "password"
      this.toggleIconTarget.classList.remove("bi-eye-slash")
      this.toggleIconTarget.classList.add("bi-eye")
    }
    console.log("Final input type:", this.keyTarget.type)
    console.log("=== End Toggle ===")
  }

  copy(event) {
    console.log("=== Copy Method Called ===")
    console.log("Event:", event)
    console.log("Event target:", event.target)

    const key = this.keyTarget.value
    console.log("Key to copy:", key)

    navigator.clipboard.writeText(key).then(() => {
      console.log("✅ Successfully copied to clipboard!")

      // Show success feedback
      const originalText = this.copyButtonTarget.innerHTML
      console.log("Original button text:", originalText)

      this.copyButtonTarget.innerHTML = '<i class="bi bi-check"></i> Copied!'
      this.copyButtonTarget.classList.remove("btn-outline-secondary")
      this.copyButtonTarget.classList.add("btn-success")
      console.log("Button updated to success state")

      setTimeout(() => {
        this.copyButtonTarget.innerHTML = originalText
        this.copyButtonTarget.classList.remove("btn-success")
        this.copyButtonTarget.classList.add("btn-outline-secondary")
        console.log("Button restored to original state")
      }, 2000)
    }).catch(err => {
      console.error("❌ Failed to copy to clipboard:", err)
    })
    console.log("=== End Copy ===")
  }

  regenerate(event) {
    console.log("=== Regenerate Method Called ===")
    console.log("Event:", event)
    if (!confirm("Are you sure you want to regenerate the API key? The old key will stop working immediately.")) {
      console.log("User cancelled regeneration")
      event.preventDefault()
    } else {
      console.log("User confirmed regeneration")
    }
    console.log("=== End Regenerate ===")
  }
}
