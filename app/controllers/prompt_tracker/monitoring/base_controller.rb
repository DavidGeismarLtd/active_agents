# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Base controller for all monitoring controllers.
    # Ensures monitoring feature is enabled before allowing access.
    class BaseController < ApplicationController
      before_action :ensure_monitoring_enabled

      private

      def ensure_monitoring_enabled
        return if PromptTracker.configuration.feature_enabled?(:monitoring)

        redirect_to testing_root_path, alert: "Monitoring is disabled."
      end
    end
  end
end
