# frozen_string_literal: true

module PromptTracker
  # ActionCable channel for real-time test run updates.
  #
  # Clients subscribe to a specific test run and receive updates when:
  # - The test run status changes
  # - Evaluators complete
  # - The test run finishes
  #
  # @example Subscribe from JavaScript
  #   consumer.subscriptions.create(
  #     { channel: "PromptTracker::TestRunChannel", test_run_id: 123 },
  #     {
  #       received(data) {
  #         console.log("Test run updated:", data);
  #         if (data.status === "completed" || data.status === "failed") {
  #           window.location.reload();
  #         }
  #       }
  #     }
  #   );
  #
  class TestRunChannel < ApplicationCable::Channel
    # Subscribe to a specific test run
    def subscribed
      test_run = TestRun.find_by(id: params[:test_run_id])

      if test_run
        stream_for test_run
      else
        reject
      end
    end

    # Unsubscribe from the test run
    def unsubscribed
      # Cleanup when channel is unsubscribed
    end
  end
end
