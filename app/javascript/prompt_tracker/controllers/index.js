// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "prompt_tracker/controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// Eager load all controllers defined in the import map under controllers/**/*_controller
eagerLoadControllersFrom("prompt_tracker/controllers", application)
