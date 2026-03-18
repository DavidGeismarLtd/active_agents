// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "prompt_tracker/controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// Manually register agent chat controller with correct namespace
import AgentChatController from "prompt_tracker/controllers/agent_chat_controller"
application.register("prompt-tracker--agent-chat", AgentChatController)

// Eager load all controllers defined in the import map under controllers/**/*_controller
eagerLoadControllersFrom("prompt_tracker/controllers", application)
