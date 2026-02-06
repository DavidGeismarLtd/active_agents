# frozen_string_literal: true

module PromptTracker
  # Helper methods for displaying model configuration in views
  module ModelConfigHelper
    # Get model configuration presenter for a prompt version
    #
    # @param version [PromptVersion] the prompt version
    # @return [ModelConfigPresenter] presenter object with all config data
    def model_config_presenter(version)
      ModelConfigPresenter.new(version)
    end

    # Presenter class for model configuration display
    class ModelConfigPresenter
      attr_reader :version, :model_config

      # @param version [PromptVersion] the prompt version
      def initialize(version)
        @version = version
        @model_config = version.model_config || {}
      end

      # Check if model config is present
      # @return [Boolean]
      def present?
        model_config.present?
      end

      # Get provider name
      # @return [String, nil]
      def provider
        model_config["provider"]
      end

      # Get API type
      # @return [String, nil]
      def api
        model_config["api"]
      end

      # Get model name
      # @return [String, nil]
      def model
        model_config["model"]
      end

      # Get temperature setting
      # @return [Float, nil]
      def temperature
        model_config["temperature"]
      end

      # Get max tokens setting
      # @return [Integer, nil]
      def max_tokens
        model_config["max_tokens"]
      end

      # Get top_p setting
      # @return [Float, nil]
      def top_p
        model_config["top_p"]
      end

      # Get frequency penalty setting
      # @return [Float, nil]
      def frequency_penalty
        model_config["frequency_penalty"]
      end

      # Get presence penalty setting
      # @return [Float, nil]
      def presence_penalty
        model_config["presence_penalty"]
      end

      # Get raw tools array
      # @return [Array]
      def raw_tools
        model_config["tools"] || []
      end

      # Get tool configuration
      # @return [Hash]
      def tool_config
        model_config["tool_config"] || {}
      end

      # Get normalized tools array (handles both string and hash formats)
      # String format: ["file_search", "functions"]
      # Hash format (from OpenAI API): [{"type"=>"file_search", "file_search"=>{...}}]
      #
      # @return [Array<String>] array of tool type strings
      def normalized_tools
        raw_tools.map do |tool|
          tool.is_a?(Hash) ? tool["type"] : tool
        end.compact
      end

      # Get API icon name for Bootstrap Icons
      # @return [String] icon name
      def api_icon
        case api
        when "chat_completions"
          "chat-dots"
        when "responses"
          "reply"
        when "assistants"
          "robot"
        else
          "gear"
        end
      end

      # Get provider color (hex code)
      # @return [String] hex color code
      def provider_color
        case provider
        when "openai"
          "#10A37F"
        when "anthropic"
          "#D97757"
        when "google"
          "#4285F4"
        else
          "#6366F1"
        end
      end

      # Get tool metadata (name, icon, color) for a tool type
      #
      # @param tool_type [String] the tool type (e.g., "file_search")
      # @return [Hash] hash with :name, :icon, :color keys
      def tool_metadata(tool_type)
        TOOL_METADATA[tool_type] || {
          name: tool_type.to_s.titleize,
          icon: "gear",
          color: "#6B7280"
        }
      end

      # Get unique accordion ID for this version
      # @return [String] unique ID for accordion element
      def accordion_id
        "tool-config-#{version.id}"
      end

      private

      # Tool metadata mapping
      TOOL_METADATA = {
        "web_search" => { name: "Web Search", icon: "globe", color: "#3B82F6" },
        "code_interpreter" => { name: "Code Interpreter", icon: "code-slash", color: "#8B5CF6" },
        "file_search" => { name: "File Search", icon: "file-earmark-text", color: "#10B981" },
        "functions" => { name: "Custom Functions", icon: "braces", color: "#F59E0B" },
        "function" => { name: "Custom Functions", icon: "braces", color: "#F59E0B" }
      }.freeze
    end
  end
end
