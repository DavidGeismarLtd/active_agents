# frozen_string_literal: true

module PromptTracker
  # Represents a deployed prompt version accessible via a unique URL.
  #
  # DeployedAgents expose prompt versions as live, interactive agents that can:
  # - Receive messages via HTTP API
  # - Execute function calls automatically
  # - Maintain conversation state
  # - Track all interactions for monitoring
  #
  # @example Deploy a prompt version
  #   agent = DeployedAgent.create!(
  #     prompt_version: version,
  #     name: "Customer Support Bot",
  #     deployment_config: {
  #       auth: { type: "api_key" },
  #       rate_limit: { requests_per_minute: 60 },
  #       conversation_ttl: 3600
  #     }
  #   )
  #   agent.public_url # => "https://app.com/agents/customer-support-bot/chat"
  #
  class DeployedAgent < ApplicationRecord
    # Temporary storage for plain API key (only available during creation)
    attr_accessor :plain_api_key

    # Associations
    belongs_to :prompt_version,
               class_name: "PromptTracker::PromptVersion",
               inverse_of: :deployed_agents

    has_many :deployed_agent_functions,
             class_name: "PromptTracker::DeployedAgentFunction",
             dependent: :destroy,
             inverse_of: :deployed_agent

    has_many :function_definitions,
             through: :deployed_agent_functions,
             class_name: "PromptTracker::FunctionDefinition"

    has_many :agent_conversations,
             class_name: "PromptTracker::AgentConversation",
             dependent: :destroy,
             inverse_of: :deployed_agent

    has_many :llm_responses,
             class_name: "PromptTracker::LlmResponse",
             dependent: :nullify,
             inverse_of: :deployed_agent

    has_many :function_executions,
             class_name: "PromptTracker::FunctionExecution",
             dependent: :nullify,
             inverse_of: :deployed_agent

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true,
                     uniqueness: true,
                     format: { with: /\A[a-z0-9-]+\z/, message: "must be lowercase alphanumeric with hyphens" }
    validates :status, inclusion: { in: %w[active paused error] }

    # Encrypted attributes
    encrypts :api_key

    # Callbacks
    before_validation :generate_slug, on: :create
    before_create :set_deployed_at
    before_create :generate_api_key
    after_create :extract_functions_from_version

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :with_errors, -> { where(status: "error") }
    scope :recent, -> { order(created_at: :desc) }

    # Use slug for URLs instead of ID
    # @return [String] the slug
    def to_param
      slug
    end

    # Generate public URL for this agent
    # @return [String] public chat endpoint URL
    def public_url
      "#{PromptTracker.configuration.agent_base_url}/agents/#{slug}/chat"
    end

    # Pause the agent (stops accepting requests)
    def pause!
      update!(status: "paused", paused_at: Time.current)
    end

    # Resume the agent (starts accepting requests)
    def resume!
      update!(status: "active", paused_at: nil, error_message: nil)
    end

    # Check if agent is currently accepting requests
    # @return [Boolean]
    def accepting_requests?
      status == "active"
    end

    # Verify API key for authentication
    # @param key [String] plain text API key
    # @return [Boolean]
    def verify_api_key(key)
      return false if api_key.blank?
      api_key == key
    end

    # Regenerate API key
    # @return [String] the new plain API key
    def regenerate_api_key!
      new_key = SecureRandom.base58(32)
      update!(api_key: new_key)
      new_key
    end

    # Get masked API key for display
    # @return [String] masked API key
    def masked_api_key
      return "Not generated" if api_key.blank?
      "sk_••••••••••••••••••••••••"
    end

    # Get deployment configuration with defaults
    # @return [Hash]
    def config
      # Convert deployment_config string keys to symbols for proper merging
      config_with_symbols = (deployment_config || {}).deep_symbolize_keys
      PromptTracker.configuration.default_deployment_config.deep_merge(config_with_symbols)
    end

    private

    def generate_slug
      return if slug.present? # Don't regenerate if slug is already set
      return if name.blank?

      # Convert to lowercase, replace underscores and spaces with hyphens, remove special chars
      base = name.downcase.gsub(/[_\s]+/, "-").gsub(/[^a-z0-9-]/, "").gsub(/-+/, "-").gsub(/^-|-$/, "")
      self.slug = base
      counter = 1
      while DeployedAgent.exists?(slug: slug)
        self.slug = "#{base}-#{counter}"
        counter += 1
      end
    end

    def set_deployed_at
      self.deployed_at = Time.current
    end

    def extract_functions_from_version
      # Link to FunctionDefinition records for functions in prompt_version.model_config.tool_config
      model_cfg = prompt_version.model_config
      tool_config = model_cfg[:tool_config] || model_cfg["tool_config"]
      return unless tool_config

      functions = tool_config[:functions] || tool_config["functions"] || []
      functions.each do |func_config|
        func_name = func_config[:name] || func_config["name"]
        next unless func_name

        func_def = FunctionDefinition.find_by(name: func_name)
        if func_def
          function_definitions << func_def unless function_definitions.include?(func_def)
        else
          Rails.logger.warn("Function '#{func_name}' not found in library for deployed agent #{id}")
        end
      end
    end

    def generate_api_key
      # Generate a secure random API key (stored encrypted)
      key = SecureRandom.base58(32)
      self.api_key = key
      @plain_api_key = key # Store temporarily for display after creation
    end
  end
end
