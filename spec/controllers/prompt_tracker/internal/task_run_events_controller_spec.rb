# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Internal
    RSpec.describe TaskRunEventsController, type: :request do
      let(:task_run) { create(:task_run, :running) }
      let(:callback_token) { "valid-token-abc123" }

      before do
        allow(CallbackTokenStore).to receive(:get).and_return(callback_token)
      end

      def post_event(event_type:, data:, token: callback_token)
        post "/prompt_tracker/internal/task_run_events",
             params: { task_run_id: task_run.id, event_type: event_type, data: data },
             headers: { "X-Callback-Token" => token },
             as: :json
      end

      describe "authentication" do
        it "rejects requests without a token" do
          post_event(event_type: "log", data: { message: "test" }, token: nil)
          expect(response).to have_http_status(:unauthorized)
        end

        it "rejects requests with an invalid token" do
          post_event(event_type: "log", data: { message: "test" }, token: "wrong-token")
          expect(response).to have_http_status(:unauthorized)
        end

        it "accepts requests with a valid token" do
          post_event(event_type: "log", data: { level: "info", message: "test" })
          expect(response).to have_http_status(:ok)
        end
      end

      describe "status_update event" do
        it "marks task run as completed" do
          post_event(
            event_type: "status_update",
            data: { status: "completed", output: "All done" }
          )

          expect(response).to have_http_status(:ok)
          task_run.reload
          expect(task_run.status).to eq("completed")
          expect(task_run.output_summary).to eq("All done")
        end

        it "marks task run as failed" do
          post_event(
            event_type: "status_update",
            data: { status: "failed", error: "Something broke" }
          )

          expect(response).to have_http_status(:ok)
          task_run.reload
          expect(task_run.status).to eq("failed")
          expect(task_run.error_message).to eq("Something broke")
        end
      end

      describe "llm_response event" do
        it "creates an LlmResponse record" do
          post_event(
            event_type: "llm_response",
            data: {
              model: "gpt-4o",
              prompt_tokens: 100,
              completion_tokens: 50,
              cost_usd: 0.003,
              text: "Here is the answer",
              context: { iteration: 1 }
            }
          )

          expect(response).to have_http_status(:ok)
          expect(task_run.llm_responses.count).to eq(1)

          llm_response = task_run.llm_responses.first
          expect(llm_response.model).to eq("gpt-4o")
          expect(llm_response.tokens_prompt).to eq(100)
          expect(llm_response.tokens_completion).to eq(50)
        end
      end

      describe "function_execution event" do
        it "creates a FunctionExecution record" do
          post_event(
            event_type: "function_execution",
            data: {
              function_name: "get_weather",
              arguments: { city: "Berlin" },
              result: { temp: 15 },
              success: true,
              execution_time_ms: 234
            }
          )

          expect(response).to have_http_status(:ok)
          expect(task_run.function_executions.count).to eq(1)

          execution = task_run.function_executions.first
          expect(execution.function_name).to eq("get_weather")
          expect(execution.success).to be true
          expect(execution.execution_time_ms).to eq(234)
        end
      end

      describe "plan_update event" do
        it "updates task run metadata with plan" do
          plan = { "steps" => [ { "name" => "Step 1", "status" => "completed" } ] }
          post_event(event_type: "plan_update", data: { plan: plan })

          expect(response).to have_http_status(:ok)
          task_run.reload
          expect(task_run.metadata["plan"]).to eq(plan)
        end
      end

      describe "log event" do
        it "appends to task run logs in metadata" do
          post_event(event_type: "log", data: { level: "info", message: "Starting task" })
          post_event(event_type: "log", data: { level: "error", message: "Something failed" })

          expect(response).to have_http_status(:ok)
          task_run.reload
          logs = task_run.metadata["logs"]
          expect(logs.length).to eq(2)
          expect(logs[0]["level"]).to eq("info")
          expect(logs[0]["message"]).to eq("Starting task")
          expect(logs[1]["level"]).to eq("error")
        end
      end

      describe "unknown event type" do
        it "returns unprocessable_entity" do
          post_event(event_type: "unknown_event", data: { foo: "bar" })
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
