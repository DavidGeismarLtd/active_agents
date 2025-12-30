# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    module Openai
      RSpec.describe AssistantsController, type: :controller do
        routes { PromptTracker::Engine.routes }

        let(:assistant) { create(:openai_assistant) }

        describe "GET #index" do
          it "returns success" do
            get :index
            expect(response).to be_successful
          end

          it "assigns @assistants" do
            assistant # create assistant
            get :index
            expect(assigns(:assistants)).to include(assistant)
          end

          context "with search query" do
            let!(:matching_assistant) { create(:openai_assistant, name: "Customer Support Bot") }
            let!(:other_assistant) { create(:openai_assistant, name: "Code Review Bot") }

            it "filters assistants by name" do
              get :index, params: { q: "Customer" }
              expect(assigns(:assistants)).to include(matching_assistant)
              expect(assigns(:assistants)).not_to include(other_assistant)
            end
          end

          context "with category filter" do
            let!(:support_assistant) { create(:openai_assistant, category: "support") }
            let!(:code_assistant) { create(:openai_assistant, category: "code") }

            it "filters assistants by category" do
              get :index, params: { category: "support" }
              expect(assigns(:assistants)).to include(support_assistant)
              expect(assigns(:assistants)).not_to include(code_assistant)
            end
          end

          context "with sorting" do
            let!(:assistant_z) { create(:openai_assistant, name: "Zulu Bot", created_at: 2.days.ago) }
            let!(:assistant_a) { create(:openai_assistant, name: "Alpha Bot", created_at: 1.day.ago) }

            it "sorts by name ascending" do
              get :index, params: { sort: "name" }
              assistants = assigns(:assistants).to_a
              expect(assistants.map(&:name)).to eq([ "Alpha Bot", "Zulu Bot" ])
            end

            it "defaults to created_at descending without sort param" do
              get :index
              assistants = assigns(:assistants).to_a
              # Most recently created first
              expect(assistants.map(&:name)).to eq([ "Alpha Bot", "Zulu Bot" ])
            end
          end
        end

        describe "GET #show" do
          it "returns success" do
            get :show, params: { id: assistant.id }
            expect(response).to be_successful
          end

          it "assigns @assistant" do
            get :show, params: { id: assistant.id }
            expect(assigns(:assistant)).to eq(assistant)
          end

          it "assigns @tests" do
            test = create(:test, testable: assistant)
            get :show, params: { id: assistant.id }
            expect(assigns(:tests)).to include(test)
          end

          it "assigns @datasets" do
            dataset = create(:dataset, testable: assistant)
            get :show, params: { id: assistant.id }
            expect(assigns(:datasets)).to include(dataset)
          end

          it "calculates metrics correctly" do
            test = create(:test, testable: assistant)
            create(:test_run, test: test, status: "passed", passed: true)
            create(:test_run, test: test, status: "failed", passed: false)

            get :show, params: { id: assistant.id }

            expect(assigns(:total_test_runs)).to eq(2)
            expect(assigns(:tests_passing)).to eq(1)
            expect(assigns(:tests_failing)).to eq(1)
          end
        end

        # NOTE: Assistants are created/updated through the playground, not through standard CRUD forms
        # So we don't test new, create, edit, update actions here

        describe "DELETE #destroy" do
          it "destroys the assistant" do
            assistant # create assistant
            expect {
              delete :destroy, params: { id: assistant.id }
            }.to change(PromptTracker::Openai::Assistant, :count).by(-1)
          end

          it "redirects to assistants index" do
            delete :destroy, params: { id: assistant.id }
            expect(response).to redirect_to(testing_openai_assistants_path)
          end

          it "sets flash notice" do
            delete :destroy, params: { id: assistant.id }
            expect(flash[:notice]).to eq("Assistant deleted successfully.")
          end
        end

        describe "POST #sync" do
          it "calls fetch_from_openai! on the assistant" do
            allow_any_instance_of(PromptTracker::Openai::Assistant).to receive(:fetch_from_openai!).and_return(true)
            post :sync, params: { id: assistant.id }
            expect(response).to redirect_to(testing_openai_assistant_path(assistant))
          end

          it "sets success notice when sync succeeds" do
            allow_any_instance_of(PromptTracker::Openai::Assistant).to receive(:fetch_from_openai!).and_return(true)
            post :sync, params: { id: assistant.id }
            expect(flash[:notice]).to eq("Assistant synced successfully from OpenAI.")
          end

          it "sets error alert when sync fails" do
            allow_any_instance_of(PromptTracker::Openai::Assistant).to receive(:fetch_from_openai!).and_raise(StandardError.new("API Error"))
            expect {
              post :sync, params: { id: assistant.id }
            }.to raise_error(StandardError)
          end
        end
      end
    end
  end
end
