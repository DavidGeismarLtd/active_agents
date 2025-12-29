# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::PromptTestsController", type: :request do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt, status: "active") }
  let(:test) { create(:prompt_test, testable: version) }

  describe "GET /versions/:version_id/tests" do
    it "returns success" do
      get "/prompt_tracker/testing/versions/#{version.id}/tests"
      expect(response).to have_http_status(:success)
    end

    it "lists all tests for the version" do
      test1 = create(:prompt_test, testable: version, name: "Test 1")
      test2 = create(:prompt_test, testable: version, name: "Test 2")

      get "/prompt_tracker/testing/versions/#{version.id}/tests"

      expect(response.body).to include("Test 1")
      expect(response.body).to include("Test 2")
    end
  end

  describe "GET /versions/:version_id/tests/:id" do
    it "shows test details" do
      get "/prompt_tracker/testing/versions/#{version.id}/tests/#{test.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(test.name)
    end
  end

  describe "POST /versions/:version_id/tests/:id/run" do
    before do
      # Stub broadcast methods to prevent Turbo Stream rendering issues in tests
      allow_any_instance_of(PromptTracker::TestRun).to receive(:broadcast_creation)
      allow_any_instance_of(PromptTracker::TestRun).to receive(:broadcast_update)
    end

    it "starts a single test in the background" do
      expect {
        post "/prompt_tracker/testing/versions/#{version.id}/tests/#{test.id}/run",
             params: { run_mode: "single", custom_variables: { name: "Test" } }
      }.to change(PromptTracker::TestRun, :count).by(1)

      expect(response).to redirect_to("/prompt_tracker/testing/prompts/#{prompt.id}/versions/#{version.id}")

      # Verify test run was created with "running" status
      test_run = PromptTracker::TestRun.last
      expect(test_run.status).to eq("running")
      expect(test_run.test).to eq(test)
    end
  end

  describe "POST /versions/:version_id/tests/run_all" do
    before do
      # Stub broadcast methods to prevent Turbo Stream rendering issues in tests
      allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_prepend_to_dataset)
      allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_replace_to_dataset)
      allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_remove_to_dataset)
      allow_any_instance_of(PromptTracker::TestRun).to receive(:broadcast_creation)
      allow_any_instance_of(PromptTracker::TestRun).to receive(:broadcast_update)
    end

    let(:dataset) { create(:dataset, testable: version) }
    let!(:dataset_row) { create(:dataset_row, dataset: dataset, row_data: { name: "Test" }) }

    it "starts all enabled tests in the background" do
      test1 = create(:prompt_test, testable: version, enabled: true, name: "Test 1")
      test2 = create(:prompt_test, testable: version, enabled: true, name: "Test 2")
      test3 = create(:prompt_test, testable: version, enabled: false, name: "Test 3")

      expect {
        post "/prompt_tracker/testing/versions/#{version.id}/tests/run_all",
             params: { dataset_id: dataset.id }
      }.to change(PromptTracker::TestRun, :count).by(2) # Only enabled tests (2 tests × 1 row)

      expect(response).to redirect_to("/prompt_tracker/testing/prompts/#{prompt.id}/versions/#{version.id}")

      # Verify test runs were created with "running" status
      test_runs = PromptTracker::TestRun.last(2)
      expect(test_runs.map(&:status)).to all(eq("running"))
    end

    it "enqueues background jobs for each enabled test" do
      create(:prompt_test, testable: version, enabled: true)
      create(:prompt_test, testable: version, enabled: true)

      post "/prompt_tracker/testing/versions/#{version.id}/tests/run_all",
           params: { dataset_id: dataset.id }

      expect(response).to redirect_to("/prompt_tracker/testing/prompts/#{prompt.id}/versions/#{version.id}")
    end

    it "shows alert when no enabled tests exist" do
      create(:prompt_test, testable: version, enabled: false)

      post "/prompt_tracker/testing/versions/#{version.id}/tests/run_all",
           params: { dataset_id: dataset.id }

      expect(response).to redirect_to("/prompt_tracker/testing/prompts/#{prompt.id}/versions/#{version.id}")
      expect(flash[:alert]).to eq("No enabled tests to run.")
    end

    it "creates test runs for all enabled tests" do
      test1 = create(:prompt_test, testable: version, enabled: true)
      test2 = create(:prompt_test, testable: version, enabled: true)

      expect {
        post "/prompt_tracker/testing/versions/#{version.id}/tests/run_all",
             params: { dataset_id: dataset.id }
      }.to change(PromptTracker::TestRun, :count).by(2)

      # Verify metadata is set correctly
      test_runs = PromptTracker::TestRun.last(2)
      expect(test_runs.map { |tr| tr.metadata["triggered_by"] }).to all(eq("run_all"))
    end
  end
end
