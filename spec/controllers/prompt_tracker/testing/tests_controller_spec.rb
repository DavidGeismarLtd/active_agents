# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Testing
    RSpec.describe TestsController, type: :controller do
      routes { PromptTracker::Engine.routes }

      let(:prompt) { create(:prompt) }
      let(:version) { create(:prompt_version, prompt: prompt, status: "active") }
      let(:test) { create(:test, testable: version) }

      describe "GET #load_more_runs" do
        let!(:test_runs) do
          # Create 12 test runs for pagination testing
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
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          expect(response).to have_http_status(:success)
          expect(response.content_type).to include("turbo-stream")
        end

        it "loads the correct number of additional runs" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          expect(assigns(:additional_runs).count).to eq(5)
        end

        it "loads runs with correct offset" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          # Should get runs 6-10 (offset 5, limit 5)
          additional_runs = assigns(:additional_runs)
          expect(additional_runs.count).to eq(5)

          # Verify they are the correct runs (ordered by created_at desc)
          all_runs = test.test_runs.order(created_at: :desc)
          expect(additional_runs.map(&:id)).to eq(all_runs[5..9].map(&:id))
        end

        it "calculates next offset correctly" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          expect(assigns(:next_offset)).to eq(10)
        end

        it "includes total runs count" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          expect(assigns(:total_runs_count)).to eq(12)
        end

        it "handles offset beyond available runs" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 20, limit: 5 },
              format: :turbo_stream

          expect(assigns(:additional_runs).count).to eq(0)
        end

        it "uses default offset and limit when not provided" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id },
              format: :turbo_stream

          # Default offset should be 5, limit should be 5
          expect(assigns(:additional_runs).count).to eq(5)
          expect(assigns(:next_offset)).to eq(10)
        end

        it "includes associated evaluations and human evaluations" do
          # Stub broadcasts to avoid missing partial errors in tests
          allow_any_instance_of(HumanEvaluation).to receive(:broadcast_human_evaluation_created)

          # Add evaluation directly to the test run
          test_runs[5].evaluations.create!(
            evaluator_type: "exact_match",
            score: 1.0,
            passed: true,
            feedback: "Match found"
          )

          # Add human evaluation to the test run (no evaluation association - belongs only to test_run)
          test_runs[5].human_evaluations.create!(score: 85, feedback: "Good response")

          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          # Verify includes are working (no N+1 queries)
          expect(assigns(:additional_runs).first.association(:human_evaluations).loaded?).to be true
          expect(assigns(:additional_runs).first.association(:evaluations).loaded?).to be true
        end

        it "assigns prompt and version for view" do
          request.headers["Accept"] = "text/vnd.turbo-stream.html"
          get :load_more_runs,
              params: { prompt_id: prompt.id, prompt_version_id: version.id, id: test.id, offset: 5, limit: 5 },
              format: :turbo_stream

          expect(assigns(:prompt)).to eq(prompt)
          expect(assigns(:version)).to eq(version)
          expect(assigns(:test)).to eq(test)
        end
      end
    end
  end
end
