# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    module Openai
      RSpec.describe AssistantTestsController, type: :controller do
        routes { PromptTracker::Engine.routes }

        let(:assistant) { create(:openai_assistant) }
        let(:test) { create(:test, testable: assistant) }
        let(:dataset) { create(:dataset, testable: assistant) }

        describe "POST #create" do
          let(:valid_params) do
            {
              assistant_id: assistant.id,
              test: {
                name: "Test Conversation Quality",
                description: "Tests conversation quality",
                enabled: true
              }
            }
          end

          it "creates a new test" do
            expect {
              post :create, params: valid_params
            }.to change(Test, :count).by(1)
          end

          it "redirects to assistant show page" do
            post :create, params: valid_params
            expect(response).to redirect_to(testing_openai_assistant_path(assistant))
          end

          it "sets flash notice" do
            post :create, params: valid_params
            expect(flash[:notice]).to eq("Test created successfully.")
          end

          context "with invalid params" do
            it "renders new template" do
              post :create, params: {
                assistant_id: assistant.id,
                test: { name: "" }
              }
              expect(response).to have_http_status(:unprocessable_entity)
            end
          end
        end

        describe "PATCH #update" do
          let(:update_params) do
            {
              assistant_id: assistant.id,
              id: test.id,
              test: {
                name: "Updated Test Name",
                description: "Updated description"
              }
            }
          end

          it "updates the test" do
            patch :update, params: update_params
            test.reload
            expect(test.name).to eq("Updated Test Name")
            expect(test.description).to eq("Updated description")
          end

          it "redirects to assistant show page" do
            patch :update, params: update_params
            expect(response).to redirect_to(testing_openai_assistant_path(assistant))
          end

          it "sets flash notice" do
            patch :update, params: update_params
            expect(flash[:notice]).to eq("Test updated successfully.")
          end

          context "with invalid params" do
            it "redirects to assistant show page" do
              patch :update, params: {
                assistant_id: assistant.id,
                id: test.id,
                test: { name: "" }
              }
              expect(response).to redirect_to(testing_openai_assistant_path(assistant))
            end
          end
        end

        describe "DELETE #destroy" do
          it "destroys the test" do
            test # create test
            expect {
              delete :destroy, params: { assistant_id: assistant.id, id: test.id }
            }.to change(Test, :count).by(-1)
          end

          it "redirects to assistant show page" do
            delete :destroy, params: { assistant_id: assistant.id, id: test.id }
            expect(response).to redirect_to(testing_openai_assistant_path(assistant))
          end

          it "sets flash notice" do
            delete :destroy, params: { assistant_id: assistant.id, id: test.id }
            expect(flash[:notice]).to eq("Test deleted successfully.")
          end
        end

        describe "POST #run" do
          context "with dataset mode" do
            let!(:dataset_row) { create(:dataset_row, dataset: dataset) }

            it "creates test runs for each dataset row" do
              expect {
                post :run, params: {
                  assistant_id: assistant.id,
                  id: test.id,
                  run_mode: "dataset",
                  dataset_id: dataset.id
                }
              }.to change(TestRun, :count).by(1)
            end

            it "enqueues RunTestJob for each row" do
              expect {
                post :run, params: {
                  assistant_id: assistant.id,
                  id: test.id,
                  run_mode: "dataset",
                  dataset_id: dataset.id
                }
              }.to have_enqueued_job(RunTestJob).exactly(1).times
            end

            it "redirects to assistant show page" do
              post :run, params: {
                assistant_id: assistant.id,
                id: test.id,
                run_mode: "dataset",
                dataset_id: dataset.id
              }
              expect(response).to redirect_to(testing_openai_assistant_path(assistant))
            end

            it "shows error when dataset_id is missing" do
              post :run, params: {
                assistant_id: assistant.id,
                id: test.id,
                run_mode: "dataset"
              }
              expect(flash[:alert]).to eq("Please select a dataset.")
            end
          end

          context "with custom mode" do
            it "creates a test run with custom variables" do
              expect {
                post :run, params: {
                  assistant_id: assistant.id,
                  id: test.id,
                  run_mode: "custom",
                  custom_variables: {
                    interlocutor_simulation_prompt: "You are a patient with a headache",
                    max_turns: "5"
                  }
                }
              }.to change(TestRun, :count).by(1)
            end

            it "stores custom variables in metadata" do
              post :run, params: {
                assistant_id: assistant.id,
                id: test.id,
                run_mode: "custom",
                custom_variables: {
                  interlocutor_simulation_prompt: "You are a patient with a headache",
                  max_turns: "5"
                }
              }
              run = TestRun.last
              expect(run.metadata["custom_variables"]["interlocutor_simulation_prompt"]).to eq("You are a patient with a headache")
              expect(run.metadata["custom_variables"]["max_turns"]).to eq("5")
            end

            it "shows error when required variables are missing" do
              post :run, params: {
                assistant_id: assistant.id,
                id: test.id,
                run_mode: "custom",
                custom_variables: {}
              }
              expect(flash[:alert]).to eq("Please provide: Interlocutor simulation prompt")
            end
          end
        end

        describe "POST #run_all" do
          let!(:test1) { create(:test, testable: assistant, enabled: true) }
          let!(:test2) { create(:test, testable: assistant, enabled: true) }
          let!(:disabled_test) { create(:test, testable: assistant, enabled: false) }
          let!(:dataset_row) { create(:dataset_row, dataset: dataset) }

          it "runs all enabled tests" do
            expect {
              post :run_all, params: {
                assistant_id: assistant.id,
                run_mode: "dataset",
                dataset_id: dataset.id
              }
            }.to change(TestRun, :count).by(2)
          end

          it "does not run disabled tests" do
            post :run_all, params: {
              assistant_id: assistant.id,
              run_mode: "dataset",
              dataset_id: dataset.id
            }
            expect(TestRun.where(test: disabled_test).count).to eq(0)
          end

          it "shows error when no enabled tests exist" do
            assistant.tests.update_all(enabled: false)
            post :run_all, params: { assistant_id: assistant.id }
            expect(flash[:alert]).to eq("No enabled tests to run.")
          end
        end

        describe "GET #load_more_runs" do
          let!(:test_runs) do
            (1..12).map do |i|
              create(:test_run,
                     test: test,
                     status: "passed",
                     created_at: i.hours.ago)
            end
          end

          it "returns turbo stream response" do
            request.headers["Accept"] = "text/vnd.turbo-stream.html"
            get :load_more_runs,
                params: { assistant_id: assistant.id, id: test.id, offset: 5, limit: 5 },
                format: :turbo_stream

            expect(response).to have_http_status(:success)
            expect(response.content_type).to include("turbo-stream")
          end

          it "loads the correct number of additional runs" do
            request.headers["Accept"] = "text/vnd.turbo-stream.html"
            get :load_more_runs,
                params: { assistant_id: assistant.id, id: test.id, offset: 5, limit: 5 },
                format: :turbo_stream

            expect(assigns(:additional_runs).count).to eq(5)
          end

          it "calculates next offset correctly" do
            request.headers["Accept"] = "text/vnd.turbo-stream.html"
            get :load_more_runs,
                params: { assistant_id: assistant.id, id: test.id, offset: 5, limit: 5 },
                format: :turbo_stream

            expect(assigns(:next_offset)).to eq(10)
          end
        end
      end
    end
  end
end
