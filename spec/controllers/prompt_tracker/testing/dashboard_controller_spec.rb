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
          it "loads both prompts and assistants" do
            prompt = create(:prompt)
            assistant = create(:openai_assistant)

            get :index, params: { filter: "all" }

            expect(assigns(:prompts)).to include(prompt)
            expect(assigns(:assistants)).to include(assistant)
          end
        end

        context "when filter is 'prompts'" do
          it "loads only prompts" do
            prompt = create(:prompt)
            assistant = create(:openai_assistant)

            get :index, params: { filter: "prompts" }

            expect(assigns(:prompts)).to include(prompt)
            expect(assigns(:assistants)).to be_empty
          end
        end

        context "when filter is 'assistants'" do
          it "loads only assistants" do
            prompt = create(:prompt)
            assistant = create(:openai_assistant)

            get :index, params: { filter: "assistants" }

            expect(assigns(:prompts)).to be_empty
            expect(assigns(:assistants)).to include(assistant)
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
            created: 3,
            updated: 2,
            total: 5,
            assistants: []
          }
        end

        before do
          allow(SyncOpenaiAssistantsService).to receive(:call).and_return(service_result)
        end

        it "calls SyncOpenaiAssistantsService" do
          expect(SyncOpenaiAssistantsService).to receive(:call)
          post :sync_openai_assistants
        end

        it "redirects to testing root with assistants filter" do
          post :sync_openai_assistants
          expect(response).to redirect_to(testing_root_path(filter: "assistants"))
        end

        it "sets success flash notice with sync details" do
          post :sync_openai_assistants
          expect(flash[:notice]).to eq("Synced 5 assistants from OpenAI (3 created, 2 updated).")
        end

        context "when sync fails" do
          before do
            allow(SyncOpenaiAssistantsService).to receive(:call)
              .and_raise(SyncOpenaiAssistantsService::SyncError, "API key not set")
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
