# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::LlmResponse, type: :model do
  let(:prompt) { create(:prompt, :with_active_version) }
  let(:version) { prompt.active_version }

  describe "scopes" do
    let!(:tracked_response) do
      create(:llm_response,
             prompt_version: version,
             is_test_run: false,
             environment: "production")
    end

    let!(:test_response) do
      create(:llm_response,
             prompt_version: version,
             is_test_run: true)
    end

    describe ".tracked_calls" do
      it "returns only non-test responses" do
        expect(described_class.tracked_calls).to contain_exactly(tracked_response)
      end

      it "excludes test run responses" do
        expect(described_class.tracked_calls).not_to include(test_response)
      end

      it "includes responses from any environment" do
        staging_response = create(:llm_response,
                                  prompt_version: version,
                                  is_test_run: false,
                                  environment: "staging")

        expect(described_class.tracked_calls).to include(tracked_response, staging_response)
      end
    end

    describe ".test_calls" do
      it "returns only test responses" do
        expect(described_class.test_calls).to contain_exactly(test_response)
      end

      it "excludes tracked call responses" do
        expect(described_class.test_calls).not_to include(tracked_response)
      end
    end

    describe "scope chaining" do
      let!(:recent_tracked) do
        create(:llm_response,
               prompt_version: version,
               is_test_run: false,
               created_at: 1.hour.ago)
      end

      let!(:old_tracked) do
        create(:llm_response,
               prompt_version: version,
               is_test_run: false,
               created_at: 2.days.ago)
      end

      it "can chain tracked_calls with recent scope" do
        recent_tracked_calls = described_class.tracked_calls.recent(24)

        expect(recent_tracked_calls).to include(recent_tracked, tracked_response)
        expect(recent_tracked_calls).not_to include(old_tracked)
      end

      it "can chain tracked_calls with successful scope" do
        tracked_response.update!(status: "success")
        recent_tracked.update!(status: "error")

        successful_tracked = described_class.tracked_calls.successful

        expect(successful_tracked).to include(tracked_response)
        expect(successful_tracked).not_to include(recent_tracked)
      end
    end
  end

  describe "semantic clarity" do
    it "tracked_calls represents calls from track_llm_call method" do
      # This test documents the semantic meaning of the scope
      # tracked_calls = responses created via PromptTracker::LlmCallService.track
      # (i.e., from the host application using track_llm_call)

      tracked = create(:llm_response,
                       prompt_version: version,
                       is_test_run: false,
                       user_id: "user123",
                       session_id: "session456")

      expect(described_class.tracked_calls).to include(tracked)
      expect(tracked.is_test_run).to be false
    end

    it "test_calls represents calls from test suite runs" do
      # This test documents the semantic meaning of the scope
      # test_calls = responses created during PromptTest execution

      test = create(:llm_response,
                    prompt_version: version,
                    is_test_run: true)

      expect(described_class.test_calls).to include(test)
      expect(test.is_test_run).to be true
    end
  end
end
