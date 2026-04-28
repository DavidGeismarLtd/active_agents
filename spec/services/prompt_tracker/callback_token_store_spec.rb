# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe CallbackTokenStore do
    let(:task_run_id) { 123 }
    let(:redis_double) { instance_double(Redis) }

    before do
      allow(Redis).to receive(:new).and_return(redis_double)
    end

    describe ".generate" do
      it "generates a hex token and stores it in Redis" do
        allow(SecureRandom).to receive(:hex).with(32).and_return("abc123token")
        expect(redis_double).to receive(:setex)
          .with("prompt_tracker:callback_token:123", 3600, "abc123token")

        token = described_class.generate(task_run_id)
        expect(token).to eq("abc123token")
      end

      it "accepts a custom TTL" do
        allow(SecureRandom).to receive(:hex).with(32).and_return("token")
        expect(redis_double).to receive(:setex)
          .with("prompt_tracker:callback_token:123", 1800, "token")

        described_class.generate(task_run_id, ttl_seconds: 1800)
      end
    end

    describe ".get" do
      it "retrieves the token from Redis" do
        expect(redis_double).to receive(:get)
          .with("prompt_tracker:callback_token:123")
          .and_return("stored_token")

        expect(described_class.get(task_run_id)).to eq("stored_token")
      end

      it "returns nil when token is expired or missing" do
        expect(redis_double).to receive(:get)
          .with("prompt_tracker:callback_token:123")
          .and_return(nil)

        expect(described_class.get(task_run_id)).to be_nil
      end
    end

    describe ".revoke" do
      it "deletes the token from Redis" do
        expect(redis_double).to receive(:del)
          .with("prompt_tracker:callback_token:123")

        described_class.revoke(task_run_id)
      end
    end
  end
end
