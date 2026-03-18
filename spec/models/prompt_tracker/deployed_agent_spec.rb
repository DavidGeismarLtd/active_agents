# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe DeployedAgent, type: :model do
    describe "associations" do
      it { is_expected.to belong_to(:prompt_version).class_name("PromptTracker::PromptVersion") }
      it { is_expected.to have_many(:deployed_agent_functions).dependent(:destroy) }
      it { is_expected.to have_many(:function_definitions).through(:deployed_agent_functions) }
      it { is_expected.to have_many(:agent_conversations).dependent(:destroy) }
      it { is_expected.to have_many(:llm_responses).dependent(:nullify) }
      it { is_expected.to have_many(:function_executions).dependent(:nullify) }
    end

    describe "validations" do
      subject { create(:deployed_agent) }

      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_uniqueness_of(:slug) }
      it { is_expected.to validate_inclusion_of(:status).in_array(%w[active paused error]) }

      it "validates slug format" do
        agent = build(:deployed_agent, slug: "Invalid Slug!")
        expect(agent).not_to be_valid
        expect(agent.errors[:slug]).to include("must be lowercase alphanumeric with hyphens")
      end

      it "allows valid slug format" do
        agent = build(:deployed_agent, slug: "valid-slug-123")
        expect(agent).to be_valid
      end
    end

    describe "callbacks" do
      describe "generate_slug" do
        it "generates slug from name on create" do
          agent = create(:deployed_agent, name: "Customer Support Bot", slug: nil)
          expect(agent.slug).to eq("customer-support-bot")
        end

        it "handles duplicate slugs by appending counter" do
          create(:deployed_agent, name: "Bot", slug: "bot")
          agent = create(:deployed_agent, name: "Bot", slug: nil)
          expect(agent.slug).to eq("bot-1")
        end

        it "does not override provided slug" do
          agent = create(:deployed_agent, name: "Test", slug: "custom-slug")
          expect(agent.slug).to eq("custom-slug")
        end
      end

      describe "set_deployed_at" do
        it "sets deployed_at on create" do
          agent = create(:deployed_agent)
          expect(agent.deployed_at).to be_present
          expect(agent.deployed_at).to be_within(1.second).of(Time.current)
        end
      end

      describe "generate_api_key" do
        it "generates api_key_digest on create" do
          agent = create(:deployed_agent)
          expect(agent.api_key_digest).to be_present
        end

        it "makes plain_api_key available after creation" do
          agent = create(:deployed_agent)
          expect(agent.plain_api_key).to be_present
          expect(agent.plain_api_key.length).to eq(32)
        end
      end

      describe "extract_functions_from_version" do
        it "links functions from prompt_version model_config" do
          func1 = create(:function_definition, name: "get_weather")
          func2 = create(:function_definition, name: "send_email")

          version = create(:prompt_version, model_config: {
            tool_config: {
              functions: [
                { name: "get_weather" },
                { name: "send_email" }
              ]
            }
          })

          agent = create(:deployed_agent, prompt_version: version)

          expect(agent.function_definitions).to include(func1, func2)
        end

        it "handles missing functions gracefully" do
          version = create(:prompt_version, model_config: {
            tool_config: {
              functions: [
                { name: "nonexistent_function" }
              ]
            }
          })

          expect {
            create(:deployed_agent, prompt_version: version)
          }.not_to raise_error
        end
      end
    end

    describe "scopes" do
      let!(:active_agent) { create(:deployed_agent, status: "active") }
      let!(:paused_agent) { create(:deployed_agent, :paused) }
      let!(:error_agent) { create(:deployed_agent, :with_error) }

      describe ".active" do
        it "returns only active agents" do
          expect(DeployedAgent.active).to contain_exactly(active_agent)
        end
      end

      describe ".paused" do
        it "returns only paused agents" do
          expect(DeployedAgent.paused).to contain_exactly(paused_agent)
        end
      end

      describe ".with_errors" do
        it "returns only agents with errors" do
          expect(DeployedAgent.with_errors).to contain_exactly(error_agent)
        end
      end

      describe ".recent" do
        it "orders by created_at desc" do
          expect(DeployedAgent.recent.first).to eq(error_agent)
        end
      end
    end

    describe "#public_url" do
      it "returns the correct public URL" do
        agent = create(:deployed_agent, slug: "my-agent")
        expected_url = "#{PromptTracker.configuration.agent_base_url}/agents/my-agent/chat"
        expect(agent.public_url).to eq(expected_url)
      end
    end

    describe "#pause!" do
      it "pauses the agent" do
        agent = create(:deployed_agent, status: "active")
        agent.pause!

        expect(agent.status).to eq("paused")
        expect(agent.paused_at).to be_present
      end
    end

    describe "#resume!" do
      it "resumes a paused agent" do
        agent = create(:deployed_agent, :paused)
        agent.resume!

        expect(agent.status).to eq("active")
        expect(agent.paused_at).to be_nil
      end

      it "clears error message" do
        agent = create(:deployed_agent, :with_error)
        agent.resume!

        expect(agent.error_message).to be_nil
      end
    end

    describe "#accepting_requests?" do
      it "returns true for active agents" do
        agent = create(:deployed_agent, status: "active")
        expect(agent.accepting_requests?).to be true
      end

      it "returns false for paused agents" do
        agent = create(:deployed_agent, :paused)
        expect(agent.accepting_requests?).to be false
      end

      it "returns false for agents with errors" do
        agent = create(:deployed_agent, :with_error)
        expect(agent.accepting_requests?).to be false
      end
    end

    describe "#verify_api_key" do
      it "verifies correct API key" do
        agent = create(:deployed_agent)
        plain_key = agent.plain_api_key

        expect(agent.verify_api_key(plain_key)).to be true
      end

      it "rejects incorrect API key" do
        agent = create(:deployed_agent)

        expect(agent.verify_api_key("wrong_key")).to be false
      end

      it "returns false when api_key_digest is blank" do
        agent = create(:deployed_agent)
        agent.update_column(:api_key_digest, nil)

        expect(agent.verify_api_key("any_key")).to be false
      end
    end

    describe "#config" do
      it "merges deployment_config with defaults" do
        agent = create(:deployed_agent, deployment_config: {
          rate_limit: { requests_per_minute: 100 }
        })

        config = agent.config
        expect(config[:rate_limit][:requests_per_minute]).to eq(100)
        expect(config[:auth][:type]).to eq("api_key")  # From defaults
        expect(config[:conversation_ttl]).to eq(3600)  # From defaults
      end
    end
  end
end
