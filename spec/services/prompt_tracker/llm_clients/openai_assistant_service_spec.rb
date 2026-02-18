# frozen_string_literal: true

require 'rails_helper'

module PromptTracker
  RSpec.describe LlmClients::OpenaiAssistantService do
    let(:assistant_id) { "asst_abc123" }
    let(:user_message) { "What's the weather in Berlin?" }
    let(:thread_id) { "thread_xyz789" }
    let(:run_id) { "run_123456" }
    let(:mock_client) { instance_double(OpenAI::Client) }

    before do
      # Mock OpenAI client
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)
      # Configure API key through the configuration system
      allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test-api-key")
    end

    describe '.call' do
      it 'creates thread, runs assistant, and returns response' do
        # Mock thread creation
        allow(mock_client).to receive(:threads).and_return(
          double(create: { 'id' => thread_id })
        )

        # Mock message creation
        allow(mock_client).to receive(:messages).and_return(
          double(
            create: { 'id' => 'msg_123' },
            list: {
              'data' => [
                {
                  'content' => [
                    { 'text' => { 'value' => 'The weather in Berlin is sunny.', 'annotations' => [] } }
                  ]
                }
              ]
            }
          )
        )

        # Mock run creation
        allow(mock_client).to receive(:runs).and_return(
          double(
            create: { 'id' => run_id },
            retrieve: {
              'id' => run_id,
              'status' => 'completed',
              'usage' => {
                'prompt_tokens' => 10,
                'completion_tokens' => 20,
                'total_tokens' => 30
              }
            }
          )
        )

        # Mock run steps (for file_search extraction)
        allow(mock_client).to receive(:run_steps).and_return(
          double(list: { 'data' => [] })
        )

        response = described_class.call(
          assistant_id: assistant_id,
          user_message: user_message
        )

        expect(response[:text]).to eq('The weather in Berlin is sunny.')
        expect(response[:usage][:prompt_tokens]).to eq(10)
        expect(response[:usage][:completion_tokens]).to eq(20)
        expect(response[:usage][:total_tokens]).to eq(30)
        expect(response[:model]).to eq(assistant_id)
        expect(response.thread_id).to eq(thread_id)
        expect(response.run_id).to eq(run_id)
        expect(response[:raw_response][:thread_id]).to eq(thread_id)
        expect(response[:raw_response][:run_id]).to eq(run_id)
      end

      it 'raises error when API key is missing' do
        allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return(nil)

        expect {
          described_class.call(assistant_id: assistant_id, user_message: user_message)
        }.to raise_error(LlmClients::OpenaiAssistantService::AssistantError, /OpenAI API key not configured/)
      end

      it 'raises error when run fails' do
        allow(mock_client).to receive(:threads).and_return(
          double(create: { 'id' => thread_id })
        )

        allow(mock_client).to receive(:messages).and_return(
          double(create: { 'id' => 'msg_123' })
        )

        allow(mock_client).to receive(:runs).and_return(
          double(
            create: { 'id' => run_id },
            retrieve: {
              'id' => run_id,
              'status' => 'failed',
              'last_error' => { 'message' => 'Something went wrong' }
            }
          )
        )

        expect {
          described_class.call(assistant_id: assistant_id, user_message: user_message)
        }.to raise_error(LlmClients::OpenaiAssistantService::AssistantError, /failed/)
      end

      it 'raises error when run times out' do
        allow(mock_client).to receive(:threads).and_return(
          double(create: { 'id' => thread_id })
        )

        allow(mock_client).to receive(:messages).and_return(
          double(create: { 'id' => 'msg_123' })
        )

        # Mock run that never completes
        allow(mock_client).to receive(:runs).and_return(
          double(
            create: { 'id' => run_id },
            retrieve: {
              'id' => run_id,
              'status' => 'in_progress'
            }
          )
        )

        # Use very short timeout for test
        expect {
          described_class.call(assistant_id: assistant_id, user_message: user_message, timeout: 1)
        }.to raise_error(LlmClients::OpenaiAssistantService::AssistantError, /timed out/)
      end

      it 'raises error when run requires action (tool calls)' do
        allow(mock_client).to receive(:threads).and_return(
          double(create: { 'id' => thread_id })
        )

        allow(mock_client).to receive(:messages).and_return(
          double(create: { 'id' => 'msg_123' })
        )

        allow(mock_client).to receive(:runs).and_return(
          double(
            create: { 'id' => run_id },
            retrieve: {
              'id' => run_id,
              'status' => 'requires_action'
            }
          )
        )

        expect {
          described_class.call(assistant_id: assistant_id, user_message: user_message)
        }.to raise_error(LlmClients::OpenaiAssistantService::AssistantError, /requires action/)
      end
    end
  end
end
