# frozen_string_literal: true

module PromptTracker
  # Manages per-run callback tokens for container -> host authentication.
  #
  # Tokens are stored in Redis with a TTL matching the task timeout.
  # This prevents replay attacks and ensures tokens expire with the task.
  #
  # @example Generate a token for a task run
  #   token = CallbackTokenStore.generate(task_run.id, ttl_seconds: 1800)
  #
  # @example Verify a token
  #   expected = CallbackTokenStore.get(task_run_id)
  #   valid = ActiveSupport::SecurityUtils.secure_compare(token, expected)
  #
  class CallbackTokenStore
    PREFIX = "prompt_tracker:callback_token:"

    # Generate a new callback token for a task run.
    #
    # @param task_run_id [Integer, String] the task run ID
    # @param ttl_seconds [Integer] time-to-live in seconds (default: 3600)
    # @return [String] the generated token
    def self.generate(task_run_id, ttl_seconds: 3600)
      token = SecureRandom.hex(32)
      redis.setex("#{PREFIX}#{task_run_id}", ttl_seconds, token)
      token
    end

    # Retrieve the callback token for a task run.
    #
    # @param task_run_id [Integer, String] the task run ID
    # @return [String, nil] the token, or nil if expired/not found
    def self.get(task_run_id)
      redis.get("#{PREFIX}#{task_run_id}")
    end

    # Revoke the callback token for a task run.
    #
    # @param task_run_id [Integer, String] the task run ID
    def self.revoke(task_run_id)
      redis.del("#{PREFIX}#{task_run_id}")
    end

    def self.redis
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end
  end
end
