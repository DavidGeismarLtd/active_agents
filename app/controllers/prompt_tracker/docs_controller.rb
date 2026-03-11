# frozen_string_literal: true

module PromptTracker
  # Controller for serving documentation pages within the PromptTracker UI.
  # Provides in-app documentation for developers on how to use the tracking features.
  class DocsController < ApplicationController
    # GET /docs/tracking
    # Shows documentation on how to track LLM calls in production code
    def tracking
      @prompt = Prompt.find_by(id: params[:prompt_id]) if params[:prompt_id]
      @version = PromptVersion.find_by(id: params[:version_id]) if params[:version_id]
    end

    # GET /docs/playground_guide
    # Shows comprehensive guide on how to create and configure agents in the playground
    def playground_guide
      # No specific prompt/version needed - this is a general guide
    end

    # GET /docs/testing_guide
    # Shows comprehensive guide on how to create and run tests for agents
    def testing_guide
      # No specific prompt/version needed - this is a general guide
    end
  end
end
