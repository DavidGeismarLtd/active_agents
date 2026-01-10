# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    RSpec.describe SingleTurnRunner, type: :service do
      let(:prompt) { create(:prompt) }
      let(:prompt_version) do
        create(:prompt_version,
          prompt: prompt,
          system_prompt: "You are a helpful assistant.",
          user_prompt: "Hello {{name}}, how can I help you?",
          model_config: { "provider" => "openai", "model" => "gpt-4o", "temperature" => 0.7 },
          variables_schema: [ { "name" => "name", "type" => "string", "required" => true } ]
        )
      end
      let(:test) { create(:test, testable: prompt_version) }
      let(:dataset) do
        create(:dataset, testable: prompt_version, custom_schema: prompt_version.variables_schema)
      end
      let(:dataset_row) do
        create(:dataset_row, dataset: dataset, row_data: { "name" => "John" })
      end
      let(:test_run) do
        create(:test_run, test: test, dataset_row: dataset_row, status: "running")
      end

      let(:runner) do
        described_class.new(
          test_run: test_run,
          test: test,
          testable: prompt_version,
          use_real_llm: false
        )
      end

      before do
        # Stub Turbo broadcasts to avoid route helper errors in tests
        allow_any_instance_of(TestRun).to receive(:broadcast_status_change)
      end

      describe "#initialize" do
        it "sets instance variables" do
          expect(runner.test_run).to eq(test_run)
          expect(runner.test).to eq(test)
          expect(runner.testable).to eq(prompt_version)
          expect(runner.use_real_llm).to be false
        end
      end

      describe "#run" do
        context "with mock LLM (use_real_llm: false)" do
          it "updates test_run status to passed when no evaluators" do
            runner.run

            test_run.reload
            expect(test_run.status).to eq("passed")
            expect(test_run.passed).to be true
          end

          it "creates an LlmResponse record" do
            expect { runner.run }.to change(LlmResponse, :count).by(1)

            llm_response = LlmResponse.last
            expect(llm_response.prompt_version).to eq(prompt_version)
            expect(llm_response.rendered_prompt).to eq("Hello John, how can I help you?")
            expect(llm_response.response_text).to eq("Mock LLM response for testing")
            expect(llm_response.status).to eq("success")
          end

          it "links LlmResponse to test_run" do
            runner.run

            test_run.reload
            expect(test_run.llm_response).to be_present
            expect(test_run.llm_response.response_text).to eq("Mock LLM response for testing")
          end

          it "records execution time" do
            runner.run

            test_run.reload
            expect(test_run.execution_time_ms).to be >= 0
          end

          it "includes provider and model in metadata" do
            runner.run

            test_run.reload
            expect(test_run.metadata["provider"]).to eq("openai")
            expect(test_run.metadata["model"]).to eq("gpt-4o")
            expect(test_run.metadata["rendered_prompt"]).to eq("Hello John, how can I help you?")
          end
        end

        context "with real LLM (use_real_llm: true)" do
          let(:runner) do
            described_class.new(
              test_run: test_run,
              test: test,
              testable: prompt_version,
              use_real_llm: true
            )
          end

          let(:mock_llm_response) do
            {
              text: "Hello John! I'm here to help you with anything you need.",
              usage: { prompt_tokens: 15, completion_tokens: 12, total_tokens: 27 },
              model: "gpt-4o",
              raw: {}
            }
          end

          before do
            allow(LlmClientService).to receive(:call).and_return(mock_llm_response)
          end

          it "calls LlmClientService with correct parameters" do
            expect(LlmClientService).to receive(:call).with(
              provider: "openai",
              model: "gpt-4o",
              prompt: "Hello John, how can I help you?",
              system_prompt: "You are a helpful assistant.",
              temperature: 0.7,
              tools: nil
            ).and_return(mock_llm_response)

            runner.run
          end

          it "creates LlmResponse with real response data" do
            runner.run

            llm_response = LlmResponse.last
            expect(llm_response.response_text).to eq("Hello John! I'm here to help you with anything you need.")
            expect(llm_response.tokens_prompt).to eq(15)
            expect(llm_response.tokens_completion).to eq(12)
          end
        end

        context "with evaluators" do
          let!(:evaluator_config) do
            create(:evaluator_config, :keyword_evaluator, configurable: test)
          end

          it "runs evaluators on response text" do
            mock_evaluator = instance_double(Evaluators::KeywordEvaluator)
            mock_evaluation = instance_double(Evaluation, score: 100, passed: true, feedback: "OK")

            allow(EvaluatorRegistry).to receive(:build).and_return(mock_evaluator)
            allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

            runner.run

            test_run.reload
            expect(test_run.metadata["evaluator_results"]).to be_present
            expect(test_run.metadata["evaluator_results"].first["passed"]).to be true
          end

          it "sets passed status when all evaluators pass" do
            mock_evaluator = instance_double(Evaluators::KeywordEvaluator)
            mock_evaluation = instance_double(Evaluation, score: 100, passed: true, feedback: "OK")

            allow(EvaluatorRegistry).to receive(:build).and_return(mock_evaluator)
            allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

            runner.run

            test_run.reload
            expect(test_run.status).to eq("passed")
            expect(test_run.passed).to be true
          end

          it "sets failed status when any evaluator fails" do
            mock_evaluator = instance_double(Evaluators::KeywordEvaluator)
            mock_evaluation = instance_double(Evaluation, score: 0, passed: false, feedback: "Missing keyword")

            allow(EvaluatorRegistry).to receive(:build).and_return(mock_evaluator)
            allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

            runner.run

            test_run.reload
            expect(test_run.status).to eq("failed")
            expect(test_run.passed).to be false
          end
        end

        context "with custom variables in metadata" do
          let(:test_run) do
            create(:test_run,
              test: test,
              dataset_row: nil,
              status: "running",
              metadata: { "custom_variables" => { "name" => "Alice" } }
            )
          end

          it "uses custom variables when dataset_row is nil" do
            runner.run

            llm_response = LlmResponse.last
            expect(llm_response.rendered_prompt).to eq("Hello Alice, how can I help you?")
          end
        end

        context "with different providers" do
          let(:prompt_version) do
            create(:prompt_version,
              prompt: prompt,
              system_prompt: "You are Claude.",
              user_prompt: "Hello {{name}}",
              model_config: { "provider" => "anthropic", "model" => "claude-3-opus" }
            )
          end

          let(:runner) do
            described_class.new(
              test_run: test_run,
              test: test,
              testable: prompt_version,
              use_real_llm: true
            )
          end

          before do
            allow(LlmClientService).to receive(:call).and_return({
              text: "Hi there!",
              usage: { prompt_tokens: 5, completion_tokens: 3, total_tokens: 8 },
              model: "claude-3-opus",
              raw: {}
            })
          end

          it "uses the correct provider from model_config" do
            expect(LlmClientService).to receive(:call).with(
              hash_including(provider: "anthropic", model: "claude-3-opus")
            )

            runner.run
          end

          it "records the provider in metadata" do
            runner.run

            test_run.reload
            expect(test_run.metadata["provider"]).to eq("anthropic")
            expect(test_run.metadata["model"]).to eq("claude-3-opus")
          end
        end

        context "with default model_config values" do
          let(:prompt_version) do
            create(:prompt_version,
              prompt: prompt,
              user_prompt: "Hello {{name}}",
              model_config: {}
            )
          end

          it "uses default provider and model when not specified" do
            runner.run

            test_run.reload
            expect(test_run.metadata["provider"]).to eq("openai")
            expect(test_run.metadata["model"]).to eq("gpt-4o")
          end
        end
      end
    end
  end
end
