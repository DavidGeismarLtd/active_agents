require 'rails_helper'

module PromptTracker
  RSpec.describe PromptGeneratorService do
    describe '.generate' do
      let(:description) { "A customer support chatbot that helps users troubleshoot technical issues" }

      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_response) { double('response', content: 'Expanded requirements') }
      let(:mock_variables_response) { double('response', content: "customer_name\nissue_type\nproduct_name") }
      let(:mock_generation_response) do
        double('response', content: {
          system_prompt: 'You are a helpful customer support assistant.',
          user_prompt: 'Hello {{ customer_name }}, I can help with {{ issue_type }}.',
          explanation: 'This prompt provides friendly customer support.'
        })
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
      end

      it 'generates prompts from a description' do
        # Step 1: Understand and expand
        expect(mock_chat).to receive(:ask).with(
          a_string_including("User's description:")
        ).and_return(mock_response)

        # Step 2: Propose variables
        expect(mock_chat).to receive(:ask).with(
          a_string_including("identify dynamic variables")
        ).and_return(mock_variables_response)

        # Step 3: Generate prompts
        expect(mock_chat).to receive(:ask).with(
          a_string_including("Create effective system and user prompts")
        ).and_return(mock_generation_response)

        result = described_class.generate(description: description)

        expect(result[:system_prompt]).to eq('You are a helpful customer support assistant.')
        expect(result[:user_prompt]).to eq('Hello {{ customer_name }}, I can help with {{ issue_type }}.')
        expect(result[:variables]).to eq([ 'customer_name', 'issue_type', 'product_name' ])
        expect(result[:explanation]).to eq('This prompt provides friendly customer support.')
      end

      it 'uses the model from configuration' do
        PromptTracker.configuration.contexts = {
          prompt_generation: {
            default_model: 'gpt-4o',
            default_temperature: 0.5
          }
        }

        expect(RubyLLM).to receive(:chat).with(model: 'gpt-4o').at_least(:once).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

        described_class.generate(description: description)
      end

      it 'uses the temperature from configuration' do
        PromptTracker.configuration.contexts = {
          prompt_generation: {
            default_model: 'gpt-4o-mini',
            default_temperature: 0.5
          }
        }

        expect(mock_chat).to receive(:with_temperature).with(0.5).at_least(:once).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

        described_class.generate(description: description)
      end

      it 'falls back to defaults when configuration is not set' do
        PromptTracker.configuration.contexts = {}

        expect(RubyLLM).to receive(:chat).with(model: 'gpt-4o-mini').at_least(:once).and_return(mock_chat)
        expect(mock_chat).to receive(:with_temperature).with(0.7).at_least(:once).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

        described_class.generate(description: description)
      end

      it 'handles descriptions with special characters' do
        special_description = "A bot that handles user's \"quotes\" and <tags>"

        allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

        result = described_class.generate(description: special_description)

        expect(result).to have_key(:system_prompt)
        expect(result).to have_key(:user_prompt)
        expect(result).to have_key(:variables)
        expect(result).to have_key(:explanation)
      end

      it 'parses variables with leading dashes' do
        variables_with_dashes = double('response', content: "- customer_name\n- issue_type\n- product_name")

        allow(mock_chat).to receive(:ask).and_return(
          mock_response,
          variables_with_dashes,
          mock_generation_response
        )

        result = described_class.generate(description: description)

        expect(result[:variables]).to eq([ 'customer_name', 'issue_type', 'product_name' ])
      end

      it 'handles empty variable lists' do
        empty_variables = double('response', content: '')

        allow(mock_chat).to receive(:ask).and_return(
          mock_response,
          empty_variables,
          mock_generation_response
        )

        result = described_class.generate(description: description)

        expect(result[:variables]).to eq([])
      end

      context 'with dynamic_configuration' do
        let(:config_provider) do
          -> {
            {
              providers: {
                openai: { api_key: 'dynamic-api-key' }
              },
              contexts: {
                prompt_generation: {
                  default_model: 'gpt-4o',
                  default_temperature: 0.9
                }
              }
            }
          }
        end

        before do
          PromptTracker.configuration.configuration_provider = config_provider
        end

        after do
          PromptTracker.configuration.configuration_provider = nil
        end

        it 'detects dynamic_configuration is enabled' do
          # Skip verification of RubyLLM.with_config (it's a gem method)
          without_partial_double_verification do
            allow(RubyLLM).to receive(:with_config).and_yield
          end

          allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

          expect(PromptTracker.configuration.dynamic_configuration?).to be true
          described_class.generate(description: description)
        end

        it 'uses the dynamically configured model' do
          # Skip verification of RubyLLM.with_config (it's a gem method)
          without_partial_double_verification do
            allow(RubyLLM).to receive(:with_config).and_yield
          end

          expect(RubyLLM).to receive(:chat).with(model: 'gpt-4o').at_least(:once).and_return(mock_chat)
          allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

          described_class.generate(description: description)
        end

        it 'uses the dynamically configured temperature' do
          # Skip verification of RubyLLM.with_config (it's a gem method)
          without_partial_double_verification do
            allow(RubyLLM).to receive(:with_config).and_yield
          end

          expect(mock_chat).to receive(:with_temperature).with(0.9).at_least(:once).and_return(mock_chat)
          allow(mock_chat).to receive(:ask).and_return(mock_response, mock_variables_response, mock_generation_response)

          described_class.generate(description: description)
        end
      end
    end
  end
end
