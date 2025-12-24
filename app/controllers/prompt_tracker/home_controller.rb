# frozen_string_literal: true

module PromptTracker
  # Home controller for the main landing page
  class HomeController < ApplicationController
    # GET /
    # Main landing page with prompts accordion
    def index
      # Load all prompts with their versions for the accordion
      @prompts = Prompt.includes(
        prompt_versions: [
          :tests,
          { tests: :test_runs }
        ]
      ).order(created_at: :desc)
    end
  end
end
