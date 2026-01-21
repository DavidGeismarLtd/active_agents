# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::LlmResponse, type: :model do
  let(:prompt) { create(:prompt, :with_active_version) }
  let(:version) { prompt.active_version }

  describe "scopes" do
    let!(:production_response) do
      create(:llm_response,
             prompt_version: version,
             environment: "production")
    end

    let!(:staging_response) do
      create(:llm_response,
             prompt_version: version,
             environment: "staging")
    end

    describe ".tracked_calls" do
      it "returns all LlmResponses (all are tracked calls)" do
        expect(described_class.tracked_calls).to contain_exactly(production_response, staging_response)
      end

      it "includes responses from any environment" do
        dev_response = create(:llm_response,
                              prompt_version: version,
                              environment: "development")

        expect(described_class.tracked_calls).to include(production_response, staging_response, dev_response)
      end
    end

    describe "scope chaining" do
      let!(:recent_tracked) do
        create(:llm_response,
               prompt_version: version,
               created_at: 1.hour.ago)
      end

      let!(:old_tracked) do
        create(:llm_response,
               prompt_version: version,
               created_at: 2.days.ago)
      end

      it "can chain tracked_calls with recent scope" do
        recent_tracked_calls = described_class.tracked_calls.recent(24)

        expect(recent_tracked_calls).to include(recent_tracked, production_response, staging_response)
        expect(recent_tracked_calls).not_to include(old_tracked)
      end

      it "can chain tracked_calls with successful scope" do
        production_response.update!(status: "success")
        staging_response.update!(status: "error")

        successful_tracked = described_class.tracked_calls.successful

        expect(successful_tracked).to include(production_response)
        expect(successful_tracked).not_to include(staging_response)
      end
    end
  end

  describe "semantic clarity" do
    it "tracked_calls represents all calls from track_llm_call method" do
      # This test documents the semantic meaning of the scope
      # tracked_calls = ALL responses created via PromptTracker::LlmCallService.track
      # (i.e., from the host application using track_llm_call)
      # Test runs store their output in TestRun.output_data instead

      tracked = create(:llm_response,
                       prompt_version: version,
                       user_id: "user123",
                       session_id: "session456")

      expect(described_class.tracked_calls).to include(tracked)
    end

    it "LlmResponse is only used for production tracking, not test runs" do
      # This test documents that test runs don't create LlmResponse records
      # Test runs store their output in TestRun.output_data instead

      # All LlmResponses are tracked calls
      response = create(:llm_response, prompt_version: version)
      expect(described_class.tracked_calls).to include(response)
      expect(described_class.count).to eq(described_class.tracked_calls.count)
    end
  end
end
