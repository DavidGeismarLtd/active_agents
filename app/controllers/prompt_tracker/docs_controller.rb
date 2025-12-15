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
  end
end
