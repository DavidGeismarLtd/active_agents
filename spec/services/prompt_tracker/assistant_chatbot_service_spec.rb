# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbotService do
  let(:session_id) { "test_session_123" }
  let(:message) { "Create a new prompt" }
    let(:context) { { page_type: :agents_list } }

  before do
    # Clear cache before each test
    Rails.cache.clear

    # By default, stub LlmClientService to avoid real network calls.
    allow(PromptTracker::LlmClientService).to receive(:call).and_return(
      instance_double(
        "NormalizedLlmResponse",
        text: "I'll help you create a prompt. What should we call it?",
        tool_calls: []
      )
    )
  end

  describe ".call" do
    context "when router cannot route to a wizard" do
        it "returns an apology and does not call the LLM" do
          allow(PromptTracker::AssistantChatbot::Router)
            .to receive(:assistant_for)
            .and_return(:no_match)

          expect(PromptTracker::LlmClientService).not_to receive(:call)

          result = described_class.call(
            message: "What's the weather?",
            session_id: session_id,
            context: { page_type: :agents_list }
          )

          expect(result.success?).to be true
          expect(result.pending_action).to be_nil
          expect(result.response).to include("I couldn't match your request")
        end
    end

      context "when router selects the docs wizard" do
        it "calls the LLM with docs context and no tools" do
          allow(PromptTracker::AssistantChatbot::Router)
            .to receive(:assistant_for)
            .and_return(:docs_wizard)

          expect(PromptTracker::LlmClientService).to receive(:call).with(
            hash_including(
              tools: [],
              system_prompt: include("PromptTracker Documentation Assistant"),
              prompt: include("/prompt_tracker/docs/testing_guide")
            )
          ).and_return(
            instance_double(
              "NormalizedLlmResponse",
              text: "See /prompt_tracker/docs/testing_guide.",
              tool_calls: []
            )
          )

          result = described_class.call(
            message: "How do I run tests?",
            session_id: session_id,
            context: { page_type: :agents_list }
          )

          expect(result.success?).to be true
          expect(result.response).to include("/prompt_tracker/docs/testing_guide")
        end
      end

    context "with a simple text response" do
      it "returns a successful result" do
        allow(PromptTracker::AssistantChatbot::Router)
          .to receive(:assistant_for)
          .and_return(:agent_creation_wizard)

        result = described_class.call(
          message: message,
          session_id: session_id,
          context: context
        )

        expect(result.success?).to be true
        expect(result.response).to eq("I'll help you create a prompt. What should we call it?")
        expect(result.error).to be_nil
      end

      it "saves the conversation to cache" do
        described_class.call(
          message: message,
          session_id: session_id,
          context: context
        )

        cached = Rails.cache.read("assistant_chatbot_conversation:#{session_id}")
        expect(cached).to be_an(Array)
        expect(cached.length).to eq(2) # user + assistant
        expect(cached[0][:role]).to eq("user")
        expect(cached[0][:content]).to eq(message)
        expect(cached[1][:role]).to eq("assistant")
      end
    end

    context "with conversation history" do
      before do
        # Pre-populate cache with history
        Rails.cache.write(
          "assistant_chatbot_conversation:#{session_id}",
          [
            { role: "user", content: "Hello" },
            { role: "assistant", content: "Hi! How can I help?" }
          ]
        )

        allow(PromptTracker::AssistantChatbot::Router)
          .to receive(:assistant_for)
          .and_return(:agent_creation_wizard)
      end

      it "includes previous conversation in LLM call" do
        described_class.call(
          message: "Create a prompt",
          session_id: session_id,
          context: context
        )

        expect(PromptTracker::LlmClientService).to have_received(:call).with(
          hash_including(
            prompt: a_string_including("Hello", "Hi! How can I help?")
          )
        )
      end

      it "appends new messages to existing history" do
        described_class.call(
          message: "Create a prompt",
          session_id: session_id,
          context: context
        )

        cached = Rails.cache.read("assistant_chatbot_conversation:#{session_id}")
        expect(cached.length).to eq(4) # 2 previous + 2 new
      end
    end

      context "with function call response" do
        context "in dataset wizard mode with a final JSON plan" do
          let(:context) do
            { page_type: :agent_version_detail, agent_version_id: 99 }
          end

          let(:json_plan) do
            {
              "agent_version_id" => 99,
              "name" => "Wizard dataset",
              "description" => "Synthetic dataset from wizard",
              "dataset_type" => "single_turn",
              "count" => 25,
              "instructions" => "Generate diverse examples",
              "model" => "gpt-4o-mini"
            }.to_json
          end

          let(:mock_llm_with_dataset_plan) do
            instance_double(
              "NormalizedLlmResponse",
              text: json_plan,
              tool_calls: []
            )
          end

          before do
            allow(PromptTracker::AssistantChatbot::Router)
              .to receive(:assistant_for)
              .and_return(:dataset_wizard)

            allow(PromptTracker::LlmClientService)
              .to receive(:call)
              .and_return(mock_llm_with_dataset_plan)
          end

          it "returns a pending_action for create_dataset built from the JSON plan" do
            result = described_class.call(
              message: "Create a dataset via wizard",
              session_id: session_id,
              context: context
            )

            expect(result.success?).to be true
            expect(result.pending_action).to be_present
            expect(result.pending_action[:function_name]).to eq("create_dataset")
            expect(result.pending_action[:arguments][:agent_version_id]).to eq(99)
            expect(result.pending_action[:arguments][:dataset_type]).to eq("single_turn")
            expect(result.pending_action[:arguments][:count]).to eq(25)
          end

          it "saves the confirmation message to history" do
            described_class.call(
              message: "Create a dataset via wizard",
              session_id: session_id,
              context: context
            )

            cached = Rails.cache.read("assistant_chatbot_conversation:#{session_id}")
            expect(cached.last[:role]).to eq("assistant")
            expect(cached.last[:content]).to include("Wizard dataset")
            expect(cached.last[:content]).to include("proceed")
          end
        end

        context "in deployment wizard mode with a final JSON plan" do
          let(:context) do
            { page_type: :agent_version_detail, agent_version_id: 42 }
          end

          let(:json_plan) do
            {
              "agent_version_id" => 42,
              "name" => "Support Agent",
              "agent_type" => "conversational",
              "deployment_config" => {
                "conversation_ttl" => 1800,
                "enable_web_ui" => true
              },
              "task_config" => nil
            }.to_json
          end

          let(:mock_llm_with_deployment_plan) do
            instance_double(
              "NormalizedLlmResponse",
              text: json_plan,
              tool_calls: []
            )
          end

          before do
            allow(PromptTracker::AssistantChatbot::Router)
              .to receive(:assistant_for)
              .and_return(:deployment_wizard)

            allow(PromptTracker::LlmClientService)
              .to receive(:call)
              .and_return(mock_llm_with_deployment_plan)
          end

          it "returns a pending_action for deploy_agent built from the JSON plan" do
            result = described_class.call(
              message: "Deploy this prompt as an agent",
              session_id: session_id,
              context: context
            )

            expect(result.success?).to be true
            expect(result.pending_action).to be_present
            expect(result.pending_action[:function_name]).to eq("deploy_agent")
            expect(result.pending_action[:arguments][:agent_version_id]).to eq(42)
            expect(result.pending_action[:arguments][:agent_type]).to eq("conversational")
          end
        end

      context "in agent creation wizard mode with a final JSON plan" do
          let(:context) do
              { page_type: :agents_list }
          end

          let(:json_plan) do
            {
              "name" => "Wizard prompt",
              "description" => "Prompt created via wizard",
              "system_prompt_concept" => "Help with customer support",
              "model" => "gpt-4o-mini",
              "temperature" => 0.5
            }.to_json
          end

          let(:mock_llm_with_prompt_plan) do
            instance_double(
              "NormalizedLlmResponse",
              text: json_plan,
              tool_calls: []
            )
          end

          before do
          allow(PromptTracker::AssistantChatbot::Router)
            .to receive(:assistant_for)
            .and_return(:agent_creation_wizard)

            allow(PromptTracker::LlmClientService)
              .to receive(:call)
              .and_return(mock_llm_with_prompt_plan)
          end

          it "returns a pending_action for create_prompt built from the JSON plan" do
            result = described_class.call(
              message: "Create a new prompt via wizard",
              session_id: session_id,
              context: context
            )

            expect(result.success?).to be true
            expect(result.pending_action).to be_present
            expect(result.pending_action[:function_name]).to eq("create_prompt")
            expect(result.pending_action[:arguments][:name]).to eq("Wizard prompt")
            expect(result.pending_action[:arguments][:system_prompt_concept]).to eq("Help with customer support")
            expect(result.pending_action[:arguments][:model]).to eq("gpt-4o-mini")
            expect(result.pending_action[:arguments][:temperature]).to eq(0.5)
          end
        end

        context "in test runner wizard mode with a final JSON plan" do
          let(:context) do
            { page_type: :agent_version_detail, agent_version_id: 27 }
          end

          let(:json_plan) do
            {
              "agent_version_id" => 27,
              "run_mode" => "dataset",
              "dataset_id" => 10,
              "test_ids" => nil,
              "execution_mode" => nil,
              "custom_variables" => nil
            }.to_json
          end

          let(:mock_llm_with_json_plan) do
            instance_double(
              "NormalizedLlmResponse",
              text: json_plan,
              tool_calls: []
            )
          end

          before do
            allow(PromptTracker::AssistantChatbot::Router)
              .to receive(:assistant_for)
              .and_return(:test_runner_wizard)

            allow(PromptTracker::LlmClientService)
              .to receive(:call)
              .and_return(mock_llm_with_json_plan)
          end

          it "returns a pending_action for run_tests built from the JSON plan" do
            result = described_class.call(
              message: "Run all tests",
              session_id: session_id,
              context: context
            )

            expect(result.success?).to be true
            expect(result.pending_action).to be_present
            expect(result.pending_action[:function_name]).to eq("run_tests")
            expect(result.pending_action[:arguments][:agent_version_id]).to eq(27)
            expect(result.pending_action[:arguments][:run_mode]).to eq("dataset")
            expect(result.pending_action[:arguments][:dataset_id]).to eq(10)
          end
        end
      end

    context "with read-only function call (no confirmation required)" do
      let(:mock_llm_with_query_call) do
        instance_double(
          "NormalizedLlmResponse",
          text: "Here's the prompt info.",
          tool_calls: [
            {
              function_name: "get_agent_version_info",
              arguments: { agent_version_id: 123 }
            }
          ]
        )
      end

      let(:mock_function_result) do
        PromptTracker::AssistantChatbot::FunctionExecutor::Result.new(
          success?: true,
          message: "Prompt version details: ...",
          links: [],
          entities_created: {},
          error: nil
        )
      end

        before do
          allow(PromptTracker::AssistantChatbot::Router)
            .to receive(:assistant_for)
            .and_return(:test_runner_wizard)

          allow(PromptTracker::LlmClientService).to receive(:call).and_return(mock_llm_with_query_call)
          allow_any_instance_of(PromptTracker::AssistantChatbot::FunctionExecutor)
            .to receive(:call)
            .and_return(mock_function_result)
        end

      it "executes immediately without confirmation" do
        result = described_class.call(
          message: "What's in prompt version 123?",
          session_id: session_id,
          context: context
        )

        expect(result.success?).to be true
        expect(result.pending_action).to be_nil
            expect(result.response).to eq("Prompt version details: ...")
      end
    end

    context "conversation history limits" do
      before do
        # Create a long conversation history
        long_history = 100.times.map do |i|
          [
            { role: "user", content: "Message #{i}" },
            { role: "assistant", content: "Response #{i}" }
          ]
        end.flatten

        Rails.cache.write(
          "assistant_chatbot_conversation:#{session_id}",
          long_history
        )
      end

      it "limits history to configured max messages" do
        described_class.call(
          message: "New message",
          session_id: session_id,
          context: context
        )

        cached = Rails.cache.read("assistant_chatbot_conversation:#{session_id}")
        # Should be limited to 50 (or configured max) plus the 2 new messages
        expect(cached.length).to be <= 52
      end
    end
  end

  describe ".execute_function" do
    let(:function_name) { "create_prompt" }
    let(:arguments) do
      {
        name: "Test Prompt",
          system_prompt_concept: "You are helpful",
        model: "gpt-4o",
        temperature: 0.7
      }
    end

    let(:mock_function_result) do
      PromptTracker::AssistantChatbot::FunctionExecutor::Result.new(
        success?: true,
        message: "Prompt created successfully!",
        links: [ { text: "View prompt", url: "/prompts/1" } ],
        entities_created: { agent_id: 1 },
        error: nil
      )
    end

    before do
      allow_any_instance_of(PromptTracker::AssistantChatbot::FunctionExecutor)
        .to receive(:call)
        .and_return(mock_function_result)
    end

    it "executes the function and returns result" do
      result = described_class.execute_function(
        session_id: session_id,
        function_name: function_name,
        arguments: arguments
      )

      expect(result.success?).to be true
      expect(result.response).to eq("Prompt created successfully!")
      expect(result.links.length).to eq(1)
    end

    it "saves the execution result to history" do
      described_class.execute_function(
        session_id: session_id,
        function_name: function_name,
        arguments: arguments
      )

      cached = Rails.cache.read("assistant_chatbot_conversation:#{session_id}")
      expect(cached).to be_present
      expect(cached.last[:role]).to eq("assistant")
      expect(cached.last[:content]).to include("Prompt created successfully")
    end

    context "when function execution fails" do
      let(:mock_error_result) do
        PromptTracker::AssistantChatbot::FunctionExecutor::Result.new(
          success?: false,
          message: nil,
          links: [],
          entities_created: {},
          error: "Failed to create agent: Name can't be blank"
        )
      end

      before do
        allow_any_instance_of(PromptTracker::AssistantChatbot::FunctionExecutor)
          .to receive(:call)
          .and_return(mock_error_result)
      end

      it "returns error result" do
        result = described_class.execute_function(
          session_id: session_id,
          function_name: function_name,
          arguments: arguments
        )

        expect(result.success?).to be false
        expect(result.error).to include("Failed to create agent")
      end
    end
  end

  describe ".generate_suggestions" do
    it "returns context-aware suggestions" do
        suggestions = described_class.generate_suggestions({ page_type: :agents_list })

      expect(suggestions).to be_an(Array)
      # Actual suggestions depend on ContextDetector implementation
    end
  end
end
