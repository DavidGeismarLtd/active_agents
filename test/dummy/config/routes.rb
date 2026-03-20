Rails.application.routes.draw do
  # Public API for deployed agents (outside engine namespace for clean URLs)
  namespace :agents do
    # GET /agents/:slug/chat - Browser chat interface (if enabled)
    # POST /agents/:slug/chat - Chat with a deployed agent (API)
    # GET /agents/:slug/info - Get agent information
    # OPTIONS /agents/:slug/chat - CORS preflight
    get ":slug/chat", to: "deployed_agents#chat", as: :chat
    post ":slug/chat", to: "deployed_agents#chat"
    get ":slug/info", to: "deployed_agents#info", as: :info
    match ":slug/chat", to: "deployed_agents#options", via: :options
  end

  mount PromptTracker::Engine => "/prompt_tracker"
end
