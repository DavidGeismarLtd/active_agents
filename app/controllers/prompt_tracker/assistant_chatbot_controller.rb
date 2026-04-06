# frozen_string_literal: true

module PromptTracker
  # Controller for the global assistant chatbot feature.
  #
  # Provides endpoints for:
  # - Sending messages and receiving AI responses
  # - Executing confirmed actions
  # - Resetting conversations
  # - Getting context-aware suggestions
  class AssistantChatbotController < ApplicationController
    # POST /assistant/chat
    # Send a message and get a response from the assistant
    def chat
      message = params[:message]
      context = extract_context

      result = AssistantChatbotService.call(
        message: message,
        session_id: session.id,
        context: context
      )

      if result.success?
        render json: {
          success: true,
            response: result.response,
          links: result.links,
          suggestions: result.suggestions,
          pending_action: result.pending_action
        }
      else
        render json: {
          success: false,
          error: result.error
        }, status: :unprocessable_entity
      end
    end

    # POST /assistant/execute_action
    # Execute a confirmed action
    def execute_action
      action_id = params[:action_id]
      function_name = params[:function_name]
      arguments = params[:arguments]
        context = extract_context

      result = AssistantChatbotService.execute_function(
        session_id: session.id,
        function_name: function_name,
          arguments: arguments,
          context: context
      )

      if result.success?
        render json: {
          success: true,
            response: result.response,
          links: result.links,
          suggestions: result.suggestions
        }
      else
        render json: {
          success: false,
          error: result.error
        }, status: :unprocessable_entity
      end
    end

    # POST /assistant/reset
    # Clear conversation history
    def reset
        cache_key = AssistantChatbotService.conversation_cache_key_for(session.id)
        Rails.cache.delete(cache_key)

      render json: {
        success: true,
        message: "Conversation reset successfully"
      }
    end

    # GET /assistant/suggestions
    # Get context-aware suggestions based on current page
    def suggestions
      context = extract_context

      suggestions = AssistantChatbotService.generate_suggestions(context)

      render json: {
        success: true,
        suggestions: suggestions
      }
    end

    private

    # Extract context from the request (URL, params, referrer)
    def extract_context
        url = request.referrer || request.url
        agent_id = params[:agent_id]
        agent_version_id = params[:version_id]

        # When calling /assistant endpoints, we typically don't have agent/version ids
        # in params, so we parse them from the referrer URL.
        if agent_id.blank? || agent_version_id.blank?
              if (match = url.match(%r{/testing/agents/(\d+)/versions/(\d+)}))
            agent_id ||= match[1]
            agent_version_id ||= match[2]
              elsif (match = url.match(%r{/testing/agents/(\d+)}))
            agent_id ||= match[1]
              end
        end

        context = {
          current_url: url,
          params: request.params.except(:controller, :action),
          agent_id: agent_id,
          version_id: agent_version_id,
          agent_version_id: agent_version_id,
          test_id: params[:test_id],
          run_id: params[:run_id],
          page_type: detect_page_type
        }

        Rails.logger.debug("[AssistantChatbot] Extracted context: #{context.inspect}")
        context
    end

    # Detect what type of page the user is on
    def detect_page_type
      url = request.referrer || request.url

      case url
      when %r{/testing/agents/\d+/versions/\d+}
        :agent_version_detail
      when %r{/testing/agents/\d+}
          :agent_detail
      when %r{/testing/agents}
          :agents_list
      when %r{/testing}
          :agents_list
      when %r{/playground}
        :playground
      when %r{/monitoring}
        :monitoring
      when %r{/agents}
        :agents
      else
        :unknown
      end
    end
  end
end
