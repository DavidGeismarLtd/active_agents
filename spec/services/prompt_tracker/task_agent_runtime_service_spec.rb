# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskAgentRuntimeService, type: :service do
  let(:agent_version) do
    create(:agent_version,
           system_prompt: "You are a helpful task automation assistant.",
           model_config: {
             provider: "openai",
             model: "gpt-4",
             temperature: 0.7
           })
  end

  let(:task_agent) do
    create(:deployed_agent,
           :task_agent,
           agent_version: agent_version,
           task_config: {
             initial_prompt: "Fetch data from {{url}} and process it",
             variables: { url: "https://example.com" },
             execution: {
               max_iterations: 3,
               timeout_seconds: 60
             },
             completion_criteria: {
               type: "auto"
             }
           })
  end

  let(:task_run) { create(:task_run, deployed_agent: task_agent) }
  let(:variables) { { url: "https://api.example.com/data" } }

  describe "#execute" do
    context "with successful single iteration" do
      it "completes task when LLM makes no function calls" do
        # Mock LLM service instance
        mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
        allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_return(mock_service)
        allow(mock_service).to receive(:call).and_return(
          PromptTracker::NormalizedLlmResponse.new(
            text: "Task completed successfully",
            model: "gpt-4",
            usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
            tool_calls: [],
            file_search_results: [],
            web_search_results: [],
            code_interpreter_results: [],
            api_metadata: {},
            raw_response: nil
          )
        )

        result = described_class.call(
          task_agent: task_agent,
          task_run: task_run,
          variables: variables
        )

        expect(result[:success]).to be true
        expect(result[:output]).to eq("Task completed successfully")
        expect(task_run.reload.status).to eq("completed")
        expect(task_run.iterations_count).to eq(1)
      end
    end

    context "with multi-turn execution" do
      it "executes multiple iterations until completion" do
        call_count = 0

        # Mock function execution to track calls
        allow_any_instance_of(described_class).to receive(:execute_function) do
          call_count += 1
          {
            success?: true,
            result: { data: "sample" },
            error: nil
          }
        end

        # Mock LLM service instance
        mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
        allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new) do |**args|
          # The executor will be called by RubyLLM when there are function calls
          # We need to simulate this by calling the executor if call_count < 2
          if call_count < 2 && args[:function_executor]
            # Simulate RubyLLM calling the executor
            args[:function_executor].call("fetch_data", {})
          end
          mock_service
        end

        # Mock LLM to return responses
        allow(mock_service).to receive(:call) do
          PromptTracker::NormalizedLlmResponse.new(
            text: call_count < 2 ? "Calling function to fetch data" : "All data processed successfully",
            model: "gpt-4",
            usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
            tool_calls: [],
            file_search_results: [],
            web_search_results: [],
            code_interpreter_results: [],
            api_metadata: {},
            raw_response: nil
          )
        end

        result = described_class.call(
          task_agent: task_agent,
          task_run: task_run,
          variables: variables
        )

        expect(result[:success]).to be true
        expect(task_run.reload.iterations_count).to eq(3)
        expect(task_run.status).to eq("completed")
      end
    end

    context "with max iterations limit" do
      it "stops execution when max_iterations is reached" do
        executor_ref = nil

        # Mock function execution
        allow_any_instance_of(described_class).to receive(:execute_function).and_return({
          success?: true,
          result: {},
          error: nil
        })

        # Mock LLM service
        allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new) do |**args|
          # Store the executor reference
          executor_ref = args[:function_executor]

          mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)

          # Mock the call method to simulate function calls
          allow(mock_service).to receive(:call) do
            # Simulate RubyLLM calling the executor (always make function calls)
            executor_ref&.call("fetch_data", {})

            PromptTracker::NormalizedLlmResponse.new(
              text: "Still working...",
              model: "gpt-4",
              usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
              tool_calls: [],
              file_search_results: [],
              web_search_results: [],
              code_interpreter_results: [],
              api_metadata: {},
              raw_response: nil
            )
          end

          mock_service
        end

        result = described_class.call(
          task_agent: task_agent,
          task_run: task_run,
          variables: variables
        )

        expect(result[:success]).to be true
        expect(result[:output]).to include("Task incomplete: Maximum iterations reached")
        expect(task_run.reload.iterations_count).to eq(3) # max_iterations from config
      end
    end

    context "with timeout" do
      it "stops execution when timeout is reached" do
        # Set very short timeout and save
        config = task_agent.task_config
        config[:execution][:timeout_seconds] = 0.1
        task_agent.update!(task_config: config)
        executor_ref = nil

        # Mock function execution
        allow_any_instance_of(described_class).to receive(:execute_function).and_return({
          success?: true,
          result: {},
          error: nil
        })

        # Mock LLM service
        allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new) do |**args|
          # Store the executor reference
          executor_ref = args[:function_executor]

          mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)

          # Mock the call method to simulate function calls with delay
          allow(mock_service).to receive(:call) do
            sleep 0.2 # Exceed timeout
            # Simulate RubyLLM calling the executor
            executor_ref&.call("fetch_data", {})

            PromptTracker::NormalizedLlmResponse.new(
              text: "Working...",
              model: "gpt-4",
              usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
              tool_calls: [],
              file_search_results: [],
              web_search_results: [],
              code_interpreter_results: [],
              api_metadata: {},
              raw_response: nil
            )
          end

          mock_service
        end

        result = described_class.call(
          task_agent: task_agent,
          task_run: task_run,
          variables: variables
        )

        expect(result[:success]).to be true
        expect(result[:output]).to include("Task incomplete: Timeout reached")
      end
    end

      context "when task run is cancelled during execution" do
        it "does not overwrite cancelled status with completed and still records output" do
          # Arrange: mock a single LLM call that will see the cancelled status
          mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
          allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_return(mock_service)

          # Simulate the autonomous loop detecting cancellation immediately
          allow_any_instance_of(described_class).to receive(:execute_autonomous_loop) do
            task_run.cancel!
            "Task cancelled by user"
          end

          result = described_class.call(
            task_agent: task_agent,
            task_run: task_run,
            variables: variables
          )

          task_run.reload
          expect(task_run.status).to eq("cancelled")
          expect(task_run.output_summary).to eq("Task cancelled by user")
          expect(result[:success]).to be true
          expect(result[:output]).to eq("Task cancelled by user")
        end
      end
  end

  describe "#enhance_system_prompt_with_iteration_context" do
    let(:service) do
      described_class.new(task_agent: task_agent, task_run: task_run, variables: variables)
    end
    let(:base_prompt) { "You are a helpful assistant." }

    context "when max_iterations is not set" do
      it "returns the system prompt unchanged" do
        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to eq(base_prompt)
      end
    end

    context "when iteration_count is 0" do
      it "returns the system prompt unchanged" do
        service.instance_variable_set(:@max_iterations, 10)
        service.instance_variable_set(:@iteration_count, 0)

        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to eq(base_prompt)
      end
    end

    context "with plenty of iterations remaining" do
      it "includes standard iteration status" do
        service.instance_variable_set(:@max_iterations, 10)
        service.instance_variable_set(:@iteration_count, 3)

        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to include("ITERATION STATUS")
        expect(result).to include("iteration 3 of 10")
        expect(result).to include("7 iterations remaining")
        expect(result).not_to include("FINAL ITERATION")
        expect(result).not_to include("ALMOST OUT OF TIME")
      end
    end

    context "on the penultimate iteration" do
      it "includes warning about almost out of time" do
        service.instance_variable_set(:@max_iterations, 5)
        service.instance_variable_set(:@iteration_count, 4)

        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to include("ALMOST OUT OF TIME")
        expect(result).to include("iteration 4 of 5")
        expect(result).to include("only 1 iteration remaining")
        expect(result).to include("Do NOT start any new major work")
      end
    end

    context "on the final iteration" do
      it "includes urgent wrap-up instructions" do
        service.instance_variable_set(:@max_iterations, 5)
        service.instance_variable_set(:@iteration_count, 5)

        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to include("FINAL ITERATION")
        expect(result).to include("LAST iteration")
        expect(result).to include("mark_task_complete()")
        expect(result).to include("Summarize what you have accomplished")
      end
    end

    context "when iteration_count exceeds max_iterations" do
      it "includes final iteration instructions" do
        service.instance_variable_set(:@max_iterations, 3)
        service.instance_variable_set(:@iteration_count, 4)

        result = service.send(:enhance_system_prompt_with_iteration_context, base_prompt)

        expect(result).to include("FINAL ITERATION")
      end
    end
  end
end
