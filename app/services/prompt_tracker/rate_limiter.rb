# frozen_string_literal: true

module PromptTracker
  # Redis-based rate limiter using sliding window algorithm.
  #
  # @example Basic usage
  #   limiter = RateLimiter.new(key: "agent:123", limit: 60, period: 60)
  #   if limiter.allow?
  #     # Process request
  #   else
  #     # Return 429 with Retry-After: limiter.retry_after
  #   end
  #
  class RateLimiter
    attr_reader :key, :limit, :period

    # @param key [String] unique identifier for the rate limit (e.g., "agent:123")
    # @param limit [Integer] maximum number of requests allowed
    # @param period [Integer] time window in seconds
    def initialize(key:, limit:, period:)
      @key = "rate_limit:#{key}"
      @limit = limit
      @period = period
    end

    # Check if request is allowed under rate limit
    # @return [Boolean] true if request is allowed
    def allow?
      return true unless redis_available?

      current_time = Time.now.to_f
      window_start = current_time - period

      redis.multi do |transaction|
        # Remove old entries outside the window
        transaction.zremrangebyscore(key, "-inf", window_start)

        # Add current request
        transaction.zadd(key, current_time, current_time)

        # Set expiration
        transaction.expire(key, period)

        # Count requests in window
        transaction.zcard(key)
      end

      # Get the count from the last command in the transaction
      count = redis.zcard(key)
      count <= limit
    end

    # Get number of seconds until rate limit resets
    # @return [Integer] seconds until retry is allowed
    def retry_after
      return 0 unless redis_available?

      current_time = Time.now.to_f
      window_start = current_time - period

      # Get the oldest request in the current window
      oldest = redis.zrange(key, 0, 0, with_scores: true).first
      return 0 unless oldest

      oldest_time = oldest[1]
      retry_time = oldest_time + period - current_time
      [ retry_time.ceil, 0 ].max
    end

    # Get current request count in window
    # @return [Integer] number of requests in current window
    def current_count
      return 0 unless redis_available?

      current_time = Time.now.to_f
      window_start = current_time - period

      redis.zremrangebyscore(key, "-inf", window_start)
      redis.zcard(key)
    end

    # Reset the rate limit
    def reset!
      return unless redis_available?

      redis.del(key)
    end

    private

    def redis
      @redis ||= Redis.new(url: redis_url)
    end

    def redis_url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    end

    def redis_available?
      redis.ping == "PONG"
    rescue Redis::CannotConnectError, Redis::TimeoutError
      Rails.logger.warn("Redis not available for rate limiting")
      false
    end
  end
end
