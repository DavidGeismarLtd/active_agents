# frozen_string_literal: true

module PromptTracker
  # Convenience module for tracking LLM calls in controllers and services.
  #
  # This module provides a simple `track_llm_call` method that wraps
  # LlmCallService.track with a cleaner syntax.
  #
  # @example Include in a controller
  #   class CustomerSupportController < ApplicationController
  #     include PromptTracker::Trackable
  #
  #     def generate_greeting
  #       result = track_llm_call(
  #         "customer_support_greeting",
  #         variables: { customer_name: params[:name] },
  #         provider: "openai",
  #         model: "gpt-4",
  #         user_id: current_user.id
  #       ) do |prompt|
  #         OpenAI::Client.new.chat(
  #           messages: [{ role: "user", content: prompt }]
  #         )
  #       end
  #
  #       render json: { greeting: result[:response_text] }
  #     end
  #   end
  #
  # @example Include in a service
  #   class EmailGeneratorService
  #     include PromptTracker::Trackable
  #
  #     def generate_email(recipient_name, topic)
  #       result = track_llm_call(
  #         "email_generator",
  #         variables: { recipient_name: recipient_name, topic: topic },
  #         provider: "anthropic",
  #         model: "claude-3-sonnet"
  #       ) do |prompt|
  #         AnthropicClient.chat(prompt)
  #       end
  #
  #       result[:response_text]
  #     end
  #   end
  #
  module Trackable
    # Track an LLM call with simplified syntax
    #
    # @param prompt_name [String] name of the prompt to use
    # @param variables [Hash] variables to render in the template (default: {})
    # @param provider [String] LLM provider (e.g., "openai", "anthropic")
    # @param model [String] model name (e.g., "gpt-4", "claude-3-opus")
    # @param version [Integer, nil] specific version number (default: nil, uses active)
    # @param user_id [String, nil] user identifier for context (default: nil)
    # @param session_id [String, nil] session identifier for context (default: nil)
    # @param environment [String, nil] environment (default: Rails.env)
    # @param metadata [Hash, nil] additional metadata to store (default: nil)
    # @yield [rendered_prompt] block that executes the LLM call
    # @yieldparam rendered_prompt [String] the rendered prompt template
    # @yieldreturn [Object] the LLM response object
    # @return [Hash] result hash with :llm_response, :response_text, :tracking_id
    # @raise [LlmCallService::PromptNotFoundError] if prompt not found
    # @raise [LlmCallService::VersionNotFoundError] if version not found
    # @raise [LlmCallService::NoBlockGivenError] if no block provided
    #
    # @example Basic usage
    # result = track_llm_call(
    #   "commercial_agent",
    #   variables: { product_description: "Amazon Echo", message: "Can I order on amazon with this ?"},
    #   provider: "openai",
    #   model: "gpt-4"
    # ) do
    #   |prompt|
    #   OpenAI::Client.new.chat(
    #     messages: [{ role: "user", content: prompt }]
    #   )
    # end
    #
    # @example With user context
    #   result = track_llm_call(
    #     "greeting",
    #     variables: { name: "Alice" },
    #     provider: "openai",
    #     model: "gpt-4",
    #     user_id: current_user.id,
    #     session_id: session.id
    #   ) { |prompt| call_openai(prompt) }
    #
    # example :
    # result = PromptTracker::LlmCallService.track(
    #   prompt_name: "customer_success",
    #   variables: { product_description: "Amazon Echo", message: "Can I order on amazon with this ?" },
    #   provider: "openai",
    #   model: "gpt-4"
    # ) do |prompt|
    #   response = PromptTracker::LlmClientService.call(
    #     provider: "openai",
    #     model: "gpt-4",
    #     prompt: prompt,
    #     temperature: 0.7
    #   )
    #   response[:text]  # Just return the text string
    # end
    def track_llm_call(prompt_name, variables: {}, provider:, model:, version: nil,
                       user_id: nil, session_id: nil, environment: nil, metadata: nil, &block)
      LlmCallService.track(
        prompt_name: prompt_name,
        variables: variables,
        provider: provider,
        model: model,
        version: version,
        user_id: user_id,
        session_id: session_id,
        environment: environment,
        metadata: metadata,
        &block
      )
    end
  end
end
