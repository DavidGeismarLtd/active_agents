# frozen_string_literal: true

# PromptTracker Configuration
#
# This file is used to configure PromptTracker settings.

PromptTracker.configure do |config|
  # Path to the directory containing prompt YAML files
  # Default: Rails.root.join("app", "prompts")
  config.prompts_path = Rails.root.join("app", "prompts")

  # Auto-sync prompts from files in development environment
  # When enabled, prompts will be automatically synced from YAML files
  # on application startup in development mode.
  # Default: true
  config.auto_sync_in_development = true

  # Auto-sync prompts from files in production environment
  # When enabled, prompts will be automatically synced from YAML files
  # on application startup in production mode.
  # WARNING: This is disabled by default for safety. In production,
  # you should sync prompts as part of your deployment process using:
  #   rake prompt_tracker:sync
  # Default: false
  config.auto_sync_in_production = false

  # Basic Authentication for Web UI
  # If both username and password are set, the web UI will require
  # HTTP Basic Authentication. If either is nil, the UI is public.
  #
  # SECURITY: It's recommended to use environment variables for credentials
  # and enable basic auth in production to protect sensitive data.
  #
  # Example with environment variables:
  #   config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  #   config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]
  #
  # Default: nil (public access)
  config.basic_auth_username = nil
  config.basic_auth_password = nil
end
