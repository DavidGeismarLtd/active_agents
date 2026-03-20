# frozen_string_literal: true

module PromptTracker
  # Represents a conversation session for a deployed agent.
  #
  # AgentConversations maintain message history and state for multi-turn
  # interactions with deployed agents. They automatically expire based on
  # the agent's TTL configuration.
  #
  # @example Creating a conversation
  #   conversation = AgentConversation.create!(
  #     deployed_agent: agent,
  #     conversation_id: SecureRandom.uuid,
  #     expires_at: 1.hour.from_now
  #   )
  #
  # @example Adding messages
  #   conversation.add_message(role: "user", content: "Hello!")
  #   conversation.add_message(role: "assistant", content: "Hi there!")
  #
  class AgentConversation < ApplicationRecord
    # Associations
    belongs_to :deployed_agent,
               class_name: "PromptTracker::DeployedAgent",
               inverse_of: :agent_conversations

    has_many :function_executions,
             class_name: "PromptTracker::FunctionExecution",
             dependent: :nullify,
             inverse_of: :agent_conversation

    has_many :llm_responses,
             class_name: "PromptTracker::LlmResponse",
             dependent: :nullify,
             inverse_of: :agent_conversation

    # Validations
    validates :conversation_id, presence: true,
                                uniqueness: { scope: :deployed_agent_id }

    # Callbacks
    before_validation :set_expires_at, on: :create, if: -> { expires_at.blank? }

    # Scopes
    scope :active, -> { where("expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }
    scope :recent, -> { order(Arel.sql("last_message_at DESC NULLS LAST")) }

    # Add a message to the conversation
    # @param role [String] message role (user, assistant, system)
    # @param content [String] message content
    # @param tool_calls [Array<Hash>] optional tool calls for assistant messages
    def add_message(role:, content:, tool_calls: nil)
      self.messages ||= []
      message = {
        "role" => role,
        "content" => content,
        "timestamp" => Time.current.iso8601
      }
      message["tool_calls"] = tool_calls if tool_calls.present?

      self.messages << message
      self.last_message_at = Time.current
      save!
    end

    # Add a tool result message
    # @param tool_call_id [String] ID of the tool call
    # @param name [String] function name
    # @param content [String] function result (JSON string)
    def add_tool_result(tool_call_id:, name:, content:)
      self.messages ||= []
      self.messages << {
        "role" => "tool",
        "tool_call_id" => tool_call_id,
        "name" => name,
        "content" => content,
        "timestamp" => Time.current.iso8601
      }
      self.last_message_at = Time.current
      save!
    end

    # Extend the conversation TTL
    def extend_ttl!
      ttl = deployed_agent.config[:conversation_ttl] || 3600
      update!(expires_at: ttl.seconds.from_now)
    end
    alias_method :extend_expiration, :extend_ttl!

    # Check if conversation is expired
    # @return [Boolean]
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Get message count
    # @return [Integer]
    def message_count
      messages&.size || 0
    end

    # Get last user message
    # @return [Hash, nil]
    def last_user_message
      messages&.reverse&.find { |m| m["role"] == "user" }
    end

    # Get last assistant message
    # @return [Hash, nil]
    def last_assistant_message
      messages&.reverse&.find { |m| m["role"] == "assistant" }
    end

    private

    def set_expires_at
      return unless deployed_agent.present?

      ttl = deployed_agent.config[:conversation_ttl] || 3600
      self.expires_at = ttl.seconds.from_now
    end
  end
end
