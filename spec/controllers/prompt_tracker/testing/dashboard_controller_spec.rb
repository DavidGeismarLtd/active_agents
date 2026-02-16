# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    RSpec.describe DashboardController, type: :controller do
      routes { PromptTracker::Engine.routes }

      describe "GET #index" do
        it "returns success" do
          get :index
          expect(response).to be_successful
        end

        it "assigns @filter with default value" do
          get :index
          expect(assigns(:filter)).to eq("all")
        end

        it "assigns @filter from params" do
          get :index, params: { filter: "prompts" }
          expect(assigns(:filter)).to eq("prompts")
        end

        context "when filter is 'all'" do
          it "loads prompts" do
            prompt = create(:prompt)

            get :index, params: { filter: "all" }

            expect(assigns(:prompts)).to include(prompt)
            # Assistants are now PromptVersions with api: "assistants", not a separate model
            expect(assigns(:assistants)).to be_empty
          end
        end

        context "when filter is 'prompts'" do
          it "loads only prompts" do
            prompt = create(:prompt)

            get :index, params: { filter: "prompts" }

            expect(assigns(:prompts)).to include(prompt)
            expect(assigns(:assistants)).to be_empty
          end
        end

        context "when filter is 'assistants'" do
          it "returns empty prompts and assistants" do
            prompt = create(:prompt)

            get :index, params: { filter: "assistants" }

            # Assistants are now PromptVersions, so both are empty when filtering by assistants
            expect(assigns(:prompts)).to be_empty
            expect(assigns(:assistants)).to be_empty
          end
        end

        it "calculates statistics" do
          get :index

          expect(assigns(:total_tests)).to be_a(Integer)
          expect(assigns(:total_runs_today)).to be_a(Integer)
          expect(assigns(:pass_rate)).to be_a(Numeric)
          expect(assigns(:prompt_count)).to be_a(Integer)
          expect(assigns(:assistant_count)).to be_a(Integer)
        end
      end

      describe "POST #sync_openai_assistants" do
        let(:service_result) do
          {
            success: true,
            created_count: 3,
            created_prompts: [],
            created_versions: [],
            errors: []
          }
        end

        let(:service_instance) { instance_double(SyncOpenaiAssistantsToPromptVersionsService, call: service_result) }

        before do
          allow(SyncOpenaiAssistantsToPromptVersionsService).to receive(:new).and_return(service_instance)
        end

        it "calls SyncOpenaiAssistantsToPromptVersionsService" do
          expect(service_instance).to receive(:call)
          post :sync_openai_assistants
        end

        it "sets success flash notice with sync details" do
          post :sync_openai_assistants
          expect(flash[:notice]).to eq("Synced 3 assistants from OpenAI.")
        end

        context "when sync fails with errors" do
          let(:service_result) do
            {
              success: false,
              created_count: 0,
              created_prompts: [],
              created_versions: [],
              errors: [ "Failed to create prompt" ]
            }
          end

          it "redirects to testing root" do
            post :sync_openai_assistants
            expect(response).to redirect_to(testing_root_path)
          end

          it "sets error flash alert" do
            post :sync_openai_assistants
            expect(flash[:alert]).to eq("Failed to sync assistants: Failed to create prompt")
          end
        end

        context "when sync raises SyncError" do
          before do
            allow(service_instance).to receive(:call)
              .and_raise(SyncOpenaiAssistantsToPromptVersionsService::SyncError, "API key not set")
          end

          it "redirects to testing root" do
            post :sync_openai_assistants
            expect(response).to redirect_to(testing_root_path)
          end

          it "sets error flash alert" do
            post :sync_openai_assistants
            expect(flash[:alert]).to eq("Failed to sync assistants: API key not set")
          end
        end
      end
    end
  end
end
