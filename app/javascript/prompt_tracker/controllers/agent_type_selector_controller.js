import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="agent-type-selector"
export default class extends Controller {
  static targets = ["taskConfig", "conversationalConfig", "planningOptions"]

  connect() {
    // Initialize visibility based on current selection
    this.toggleType()
    this.togglePlanning()
  }

  toggleType() {
    const selectedType = this.element.querySelector('input[name="deployed_agent[agent_type]"]:checked')?.value

    if (selectedType === "task") {
      this.showTaskConfig()
    } else {
      this.showConversationalConfig()
    }
  }

  togglePlanning() {
    const planningEnabled = this.element.querySelector('input[name="deployed_agent[task_config][planning][enabled]"]')?.checked

    if (this.hasPlanningOptionsTarget) {
      this.planningOptionsTarget.style.display = planningEnabled ? "block" : "none"
    }
  }

  showTaskConfig() {
    if (this.hasTaskConfigTarget) {
      this.taskConfigTarget.style.display = "block"
    }
    if (this.hasConversationalConfigTarget) {
      this.conversationalConfigTarget.style.display = "none"
    }
  }

  showConversationalConfig() {
    if (this.hasTaskConfigTarget) {
      this.taskConfigTarget.style.display = "none"
    }
    if (this.hasConversationalConfigTarget) {
      this.conversationalConfigTarget.style.display = "block"
    }
  }
}
