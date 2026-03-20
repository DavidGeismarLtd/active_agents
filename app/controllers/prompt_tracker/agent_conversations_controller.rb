# frozen_string_literal: true

module PromptTracker
  # Controller for viewing agent conversation details
  class AgentConversationsController < ApplicationController
    before_action :set_conversation

    # GET /agent_conversations/:id
    # Show conversation details with full message history
    def show
      @agent = @conversation.deployed_agent
      @messages = @conversation.messages || []
    end

    private

    def set_conversation
      @conversation = AgentConversation.find(params[:id])
    end
  end
end
