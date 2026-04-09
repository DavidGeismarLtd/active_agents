// PromptTracker main JavaScript entry point
// Uses bare specifiers (e.g. "prompt_tracker/controllers") resolved by importmap
// Works with both importmap-rails gem AND native browser importmaps

import "@hotwired/turbo-rails"

// Import and register all Stimulus controllers
import "prompt_tracker/controllers"

// Import Chart.js UMD bundle (automatically assigns to window.Chart)
import "chart.js"

// Import custom Turbo Stream actions
import "prompt_tracker/turbo_streams/close_modal"
