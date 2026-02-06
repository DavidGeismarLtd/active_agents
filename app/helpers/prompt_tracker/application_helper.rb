# frozen_string_literal: true

module PromptTracker
  # Application-wide helper methods for PromptTracker views
  module ApplicationHelper
    include ModelConfigHelper
    include PlaygroundHelper
    # Format USD amount with dollar sign
    #
    # @param amount [Float, nil] the amount in USD
    # @return [String] formatted amount (e.g., "$1.23")
    # @example
    #   format_cost(1.234) # => "$1.23"
    #   format_cost(nil) # => "$0.00"
    def format_cost(amount)
      return "$0.00" if amount.nil?

      "$#{format('%.4f', amount)}"
    end

    # Format duration in milliseconds to human-readable format
    #
    # @param ms [Integer, Float, nil] duration in milliseconds
    # @return [String] formatted duration
    # @example
    #   format_duration(1234) # => "1.23s"
    #   format_duration(234) # => "234ms"
    #   format_duration(nil) # => "N/A"
    def format_duration(ms)
      return "N/A" if ms.nil?

      if ms >= 1000
        "#{(ms / 1000.0).round(2)}s"
      else
        "#{ms.round}ms"
      end
    end

    # Format token count with commas
    #
    # @param count [Integer, nil] token count
    # @return [String] formatted count
    # @example
    #   format_tokens(1234) # => "1,234"
    #   format_tokens(nil) # => "0"
    def format_tokens(count)
      return "0" if count.nil?

      count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    # Generate HTML badge for status
    #
    # @param status [String] the status value
    # @return [String] HTML badge
    # @example
    #   status_badge("active") # => "<span class='badge badge-success'>active</span>"
    def status_badge(status)
      color = case status.to_s
      when "active" then "success"
      when "deprecated" then "warning"
      when "draft" then "secondary"
      when "archived" then "dark"
      when "pending" then "info"
      when "completed" then "success"
      when "failed" then "danger"
      else "secondary"
      end

      content_tag(:span, status, class: "badge badge-#{color}")
    end

    # Generate colored badge for score
    #
    # @param score [Float] the score value
    # @param min [Float] minimum score
    # @param max [Float] maximum score
    # @return [String] HTML badge with color
    # @example
    #   score_badge(4.5, 0, 5) # => "<span class='badge badge-success'>4.5</span>"
    def score_badge(score, min = 0, max = 5)
      return content_tag(:span, "N/A", class: "badge badge-secondary") if score.nil?

      percentage = ((score - min) / (max - min) * 100).round
      color = if percentage >= 80
                "success"
      elsif percentage >= 60
                "primary"
      elsif percentage >= 40
                "warning"
      else
                "danger"
      end

      content_tag(:span, score.round(2), class: "badge badge-#{color}")
    end

    # Get icon for provider
    #
    # @param provider [String] the provider name
    # @return [String] icon class or emoji
    # @example
    #   provider_icon("openai") # => "🤖"
    def provider_icon(provider)
      case provider.to_s.downcase
      when "openai" then "🤖"
      when "anthropic" then "🧠"
      when "google" then "🔍"
      when "cohere" then "💬"
      else "🔮"
      end
    end



    # Format percentage
    #
    # @param value [Float] the percentage value (0-100)
    # @return [String] formatted percentage
    # @example
    #   format_percentage(85.5) # => "85.5%"
    def format_percentage(value)
      return "N/A" if value.nil?

      "#{value.round(1)}%"
    end

    # Calculate percentage change between two values
    #
    # @param old_value [Float] the old value
    # @param new_value [Float] the new value
    # @return [String] formatted percentage change with + or -
    # @example
    #   percentage_change(100, 120) # => "+20.0%"
    #   percentage_change(100, 80) # => "-20.0%"
    def percentage_change(old_value, new_value)
      return "N/A" if old_value.nil? || new_value.nil? || old_value.zero?

      change = ((new_value - old_value) / old_value.to_f * 100).round(1)
      sign = change.positive? ? "+" : ""
      "#{sign}#{change}%"
    end

    # Truncate text with ellipsis
    #
    # @param text [String] the text to truncate
    # @param length [Integer] maximum length
    # @return [String] truncated text
    def truncate_text(text, length = 100)
      return "" if text.nil?

      text.length > length ? "#{text[0...length]}..." : text
    end

    # Format timestamp
    #
    # @param time [Time, nil] the timestamp
    # @return [String] formatted time
    # @example
    #   format_timestamp(Time.now) # => "2025-01-08 14:30"
    def format_timestamp(time)
      return "N/A" if time.nil?

      time.strftime("%Y-%m-%d %H:%M")
    end

    # Format relative time
    #
    # @param time [Time, nil] the timestamp
    # @return [String] relative time (e.g., "2 hours ago")
    def format_relative_time(time)
      return "N/A" if time.nil?

      time_ago_in_words(time) + " ago"
    end

    # Check if a provider has an API key configured.
    #
    # @param provider [String, Symbol] the provider name
    # @return [Boolean] true if API key is present
    # @example
    #   provider_api_key_present?("openai") # => true
    #   provider_api_key_present?(:anthropic) # => false
    def provider_api_key_present?(provider)
      PromptTracker.configuration.provider_configured?(provider)
    end

    # Get list of available providers for a given context.
    # Returns providers that have API keys configured AND are allowed by the context.
    #
    # @param context [Symbol] the context name (e.g., :playground, :llm_judge)
    # @return [Array<Symbol>] list of provider keys
    # @example
    #   providers_for(:playground) # => [:openai, :anthropic]
    #   providers_for(:llm_judge) # => [:openai]
    def providers_for(context)
      PromptTracker.configuration.providers_for(context)
    end

    # Get list of available providers (those with API keys configured).
    # @deprecated Use {#providers_for} with a context instead
    # @return [Array<Symbol>] list of provider keys
    def available_providers
      PromptTracker.configuration.configured_providers
    end

    # Get available models for a context.
    # Returns models that are allowed by the context AND whose provider has an API key.
    #
    # @param context [Symbol] the context name (e.g., :playground, :llm_judge)
    # @param provider [Symbol, nil] optional provider filter
    # @return [Hash, Array] hash of provider => models, or array if provider specified
    # @example
    #   models_for(:playground) # => { openai: [...], anthropic: [...] }
    #   models_for(:playground, provider: :openai) # => [{ id: "gpt-4o", ... }]
    def models_for(context, provider: nil)
      PromptTracker.configuration.models_for(context, provider: provider)
    end

    # Get the default model for a context.
    #
    # @param context [Symbol] the context name
    # @return [String, nil] the default model ID
    # @example
    #   default_model_for(:playground) # => "gpt-4o"
    def default_model_for(context)
      PromptTracker.configuration.default_model_for(context)
    end

    # Get the default provider for a context.
    #
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default provider
    # @example
    #   default_provider_for(:playground) # => :openai
    def default_provider_for(context)
      PromptTracker.configuration.default_provider_for(context)
    end

    # Get the default API for a context.
    #
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default API
    # @example
    #   default_api_for(:playground) # => :chat_completion
    def default_api_for(context)
      PromptTracker.configuration.default_api_for(context)
    end

    # Get the display name for a provider.
    #
    # @param provider [Symbol] the provider key
    # @return [String] the provider display name
    # @example
    #   provider_name(:openai) # => "OpenAI"
    def provider_name(provider)
      PromptTracker.configuration.provider_name(provider)
    end

    # Get available APIs for a provider.
    #
    # @param provider [Symbol] the provider key
    # @return [Array<Hash>] array of API hashes with :key, :name, :default, :capabilities
    # @example
    #   apis_for(:openai) # => [{ key: :chat_completion, name: "Chat Completions", ... }]
    def apis_for(provider)
      PromptTracker.configuration.apis_for(provider)
    end

    # Get the default API for a provider.
    #
    # @param provider [Symbol] the provider key
    # @return [Symbol, nil] the default API key
    # @example
    #   default_api_for_provider(:openai) # => :chat_completion
    def default_api_for_provider(provider)
      PromptTracker.configuration.default_api_for_provider(provider)
    end

    # Check if a provider has multiple APIs.
    #
    # @param provider [Symbol] the provider key
    # @return [Boolean] true if provider has more than one API
    # @example
    #   provider_has_multiple_apis?(:openai) # => true
    #   provider_has_multiple_apis?(:anthropic) # => false
    def provider_has_multiple_apis?(provider)
      PromptTracker.configuration.provider_has_multiple_apis?(provider)
    end

    # Get models for a specific provider and API combination.
    #
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [Array<Hash>] array of model hashes compatible with the API
    # @example
    #   models_for_api(:openai, :chat_completion) # => [{ id: "gpt-4o", ... }]
    def models_for_api(provider, api)
      PromptTracker.configuration.models_for_api(provider, api)
    end

    # Get all provider/API combinations for the UI.
    #
    # @return [Array<Hash>] array of hashes with provider and API info
    def all_provider_api_options
      PromptTracker.configuration.all_provider_api_options
    end

    # Highlight variable values in rendered prompt
    #
    # @param rendered_prompt [String] the rendered prompt text
    # @param variables_used [Hash] the variables that were used
    # @return [String] HTML with highlighted variables
    # @example
    #   highlight_variables("Hello John", { "name" => "John" })
    #   # => "Hello <mark>John</mark>"
    def highlight_variables(rendered_prompt, variables_used)
      return rendered_prompt if variables_used.blank?

      result = rendered_prompt.dup

      # Sort variables by value length (longest first) to avoid partial replacements
      sorted_vars = variables_used.sort_by { |_k, v| -v.to_s.length }

      sorted_vars.each do |_key, value|
        next if value.blank?

        # Escape the value for regex and HTML
        escaped_value = Regexp.escape(value.to_s)

        # Replace all occurrences with highlighted version
        result = result.gsub(/#{escaped_value}/) do |match|
          "<mark style='background-color: #FEF3C7; padding: 2px 4px; border-radius: 3px; font-weight: 500;'>#{ERB::Util.html_escape(match)}</mark>"
        end
      end

      result.html_safe
    end
  end
end
