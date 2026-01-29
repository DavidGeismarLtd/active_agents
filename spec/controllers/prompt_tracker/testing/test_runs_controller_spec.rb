# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    RSpec.describe TestRunsController, type: :controller do
      routes { PromptTracker::Engine.routes }

      let(:prompt) { create(:prompt) }
      let(:version) { create(:prompt_version, prompt: prompt) }
      let(:test) { create(:test, testable: version) }
      let(:dataset) { create(:dataset, testable: version) }
      let(:dataset_row) { create(:dataset_row, dataset: dataset) }

      describe "POST #rerun" do
        context "with dataset mode test run" do
          let!(:test_run) do
            create(:test_run,
                   test: test,
                   dataset: dataset,
                   dataset_row: dataset_row,
                   status: "passed",
                   metadata: {
                     triggered_by: "manual",
                     user: "web_ui",
                     run_mode: "dataset"
                   })
          end

          it "creates a new test run with the same configuration" do
            initial_count = TestRun.count
            post :rerun, params: { id: test_run.id }
            expect(TestRun.count).to eq(initial_count + 1)

            new_run = TestRun.last
            expect(new_run.test).to eq(test)
            expect(new_run.dataset).to eq(dataset)
            expect(new_run.dataset_row).to eq(dataset_row)
            expect(new_run.status).to eq("running")
            expect(new_run.metadata["run_mode"]).to eq("dataset")
            expect(new_run.metadata["triggered_by"]).to eq("rerun")
            expect(new_run.metadata["original_test_run_id"]).to eq(test_run.id)
          end

          it "enqueues RunTestJob" do
            expect {
              post :rerun, params: { id: test_run.id }
            }.to have_enqueued_job(RunTestJob).exactly(1).times
          end

          it "redirects to the testable show page" do
            post :rerun, params: { id: test_run.id }
            expect(response).to redirect_to(testing_prompt_prompt_version_path(prompt, version))
          end

          it "sets a success notice" do
            post :rerun, params: { id: test_run.id }
            expect(flash[:notice]).to eq("Test re-run queued successfully.")
          end
        end

        context "with custom variables mode test run" do
          let(:custom_vars) { { "customer_name" => "Alice", "issue" => "billing" } }
          let!(:test_run) do
            create(:test_run,
                   test: test,
                   status: "passed",
                   metadata: {
                     triggered_by: "manual",
                     user: "web_ui",
                     run_mode: "custom",
                     custom_variables: custom_vars
                   })
          end

          it "creates a new test run with the same custom variables" do
            initial_count = TestRun.count
            post :rerun, params: { id: test_run.id }
            expect(TestRun.count).to eq(initial_count + 1)

            new_run = TestRun.last
            expect(new_run.test).to eq(test)
            expect(new_run.dataset).to be_nil
            expect(new_run.dataset_row).to be_nil
            expect(new_run.status).to eq("running")
            expect(new_run.metadata["run_mode"]).to eq("custom")
            expect(new_run.metadata["custom_variables"]).to eq(custom_vars)
            expect(new_run.metadata["triggered_by"]).to eq("rerun")
            expect(new_run.metadata["original_test_run_id"]).to eq(test_run.id)
          end
        end

        context "with assistant testable" do
          let(:assistant) { create(:openai_assistant) }
          let(:assistant_test) { create(:test, testable: assistant) }
          let(:assistant_dataset) { create(:dataset, testable: assistant) }
          let(:assistant_dataset_row) { create(:dataset_row, dataset: assistant_dataset) }
          let!(:test_run) do
            create(:test_run,
                   test: assistant_test,
                   dataset: assistant_dataset,
                   dataset_row: assistant_dataset_row,
                   status: "passed",
                   metadata: {
                     triggered_by: "manual",
                     user: "web_ui",
                     run_mode: "dataset"
                   })
          end

          it "redirects to the assistant show page" do
            post :rerun, params: { id: test_run.id }
            expect(response).to redirect_to(testing_openai_assistant_path(assistant))
          end
        end
      end
    end
  end
end
