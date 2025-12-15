# frozen_string_literal: true

module PromptTracker
  module Concerns
    # Basic authentication concern for PromptTracker controllers.
    #
    # This module provides HTTP Basic Authentication for the PromptTracker web UI.
    # Authentication is only enabled if both username and password are configured
    # in the PromptTracker configuration.
    #
    # @example Enable basic auth in an initializer
    #   PromptTracker.configure do |config|
    #     config.basic_auth_username = "admin"
    #     config.basic_auth_password = "secret"
    #   end
    #
    # @example Disable basic auth (default)
    #   PromptTracker.configure do |config|
    #     config.basic_auth_username = nil
    #     config.basic_auth_password = nil
    #   end
    #
    module BasicAuthentication
      extend ActiveSupport::Concern

      included do
        before_action :authenticate_if_configured
      end

      private

      # Authenticate using HTTP Basic Auth if credentials are configured.
      # If credentials are not configured, this method does nothing (public access).
      def authenticate_if_configured
        return unless PromptTracker.configuration.basic_auth_enabled?

        authenticate_or_request_with_http_basic("PromptTracker") do |username, password|
          username == PromptTracker.configuration.basic_auth_username &&
            password == PromptTracker.configuration.basic_auth_password
        end
      end
    end
  end
end
