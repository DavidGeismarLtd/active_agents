# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe "BasicAuthentication", type: :request do
    before do
      @original_username = PromptTracker.configuration.basic_auth_username
      @original_password = PromptTracker.configuration.basic_auth_password
    end

    after do
      PromptTracker.configuration.basic_auth_username = @original_username
      PromptTracker.configuration.basic_auth_password = @original_password
    end

    describe "when basic auth is not configured" do
      it "allows access" do
        PromptTracker.configuration.basic_auth_username = nil
        PromptTracker.configuration.basic_auth_password = nil

        get "/prompt_tracker/testing/prompts"
        expect(response).to have_http_status(:success)
      end
    end

    describe "when credentials are configured" do
      before do
        PromptTracker.configuration.basic_auth_username = "admin"
        PromptTracker.configuration.basic_auth_password = "secret"
      end

      it "requires authentication" do
        get "/prompt_tracker/testing/prompts"
        expect(response).to have_http_status(:unauthorized)
      end

      it "allows access with correct credentials" do
        credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
        get "/prompt_tracker/testing/prompts", headers: { "HTTP_AUTHORIZATION" => credentials }
        expect(response).to have_http_status(:success)
      end

      it "denies access with incorrect username" do
        credentials = ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "secret")
        get "/prompt_tracker/testing/prompts", headers: { "HTTP_AUTHORIZATION" => credentials }
        expect(response).to have_http_status(:unauthorized)
      end

      it "denies access with incorrect password" do
        credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong")
        get "/prompt_tracker/testing/prompts", headers: { "HTTP_AUTHORIZATION" => credentials }
        expect(response).to have_http_status(:unauthorized)
      end

      it "protects all routes when enabled" do
        get "/prompt_tracker/testing/prompts"
        expect(response).to have_http_status(:unauthorized)

        get "/prompt_tracker/monitoring/responses"
        expect(response).to have_http_status(:unauthorized)

        get "/prompt_tracker/evaluations"
        expect(response).to have_http_status(:unauthorized)

        get "/prompt_tracker/testing"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "#basic_auth_enabled?" do
      it "returns true when both credentials are set" do
        PromptTracker.configuration.basic_auth_username = "admin"
        PromptTracker.configuration.basic_auth_password = "secret"

        expect(PromptTracker.configuration.basic_auth_enabled?).to be true
      end

      it "returns false when username is nil" do
        PromptTracker.configuration.basic_auth_username = nil
        PromptTracker.configuration.basic_auth_password = "secret"

        expect(PromptTracker.configuration.basic_auth_enabled?).to be false
      end

      it "returns false when password is nil" do
        PromptTracker.configuration.basic_auth_username = "admin"
        PromptTracker.configuration.basic_auth_password = nil

        expect(PromptTracker.configuration.basic_auth_enabled?).to be false
      end

      it "returns false when both are nil" do
        PromptTracker.configuration.basic_auth_username = nil
        PromptTracker.configuration.basic_auth_password = nil

        expect(PromptTracker.configuration.basic_auth_enabled?).to be false
      end
    end
  end
end
