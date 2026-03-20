# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe AgentConversation, type: :model do
    describe "associations" do
      subject { build(:agent_conversation) }

      it { is_expected.to belong_to(:deployed_agent).class_name("PromptTracker::DeployedAgent") }
      it { is_expected.to have_many(:llm_responses).dependent(:nullify) }
      it { is_expected.to have_many(:function_executions).dependent(:nullify) }
    end

    describe "validations" do
      subject { build(:agent_conversation) }

      it { is_expected.to validate_presence_of(:conversation_id) }
      it { is_expected.to validate_uniqueness_of(:conversation_id).scoped_to(:deployed_agent_id) }
    end

    describe "callbacks" do
      describe "set_expires_at" do
        it "sets expires_at based on deployed_agent config" do
          agent = create(:deployed_agent, deployment_config: {
            conversation_ttl: 7200  # 2 hours
          })
          conversation = create(:agent_conversation, deployed_agent: agent)

          expect(conversation.expires_at).to be_present
          expect(conversation.expires_at).to be_within(5.seconds).of(2.hours.from_now)
        end

        it "uses default TTL if not configured" do
          agent = create(:deployed_agent, deployment_config: {})
          conversation = create(:agent_conversation, deployed_agent: agent)

          expect(conversation.expires_at).to be_present
          expect(conversation.expires_at).to be_within(5.seconds).of(1.hour.from_now)
        end
      end
    end

    describe "scopes" do
      let!(:active_conversation) { create(:agent_conversation, expires_at: 1.hour.from_now) }
      let!(:expired_conversation) { create(:agent_conversation, :expired) }

      describe ".active" do
        it "returns only non-expired conversations" do
          expect(AgentConversation.active).to contain_exactly(active_conversation)
        end
      end

      describe ".expired" do
        it "returns only expired conversations" do
          expect(AgentConversation.expired).to contain_exactly(expired_conversation)
        end
      end

      describe ".recent" do
        it "orders by last_message_at desc" do
          old_conv = create(:agent_conversation, last_message_at: 1.hour.ago)
          new_conv = create(:agent_conversation, last_message_at: 5.minutes.ago)

          expect(AgentConversation.recent).to eq([ new_conv, old_conv, active_conversation, expired_conversation ])
        end
      end
    end

    describe "#expired?" do
      it "returns true when expires_at is in the past" do
        conversation = create(:agent_conversation, :expired)
        expect(conversation.expired?).to be true
      end

      it "returns false when expires_at is in the future" do
        conversation = create(:agent_conversation, expires_at: 1.hour.from_now)
        expect(conversation.expired?).to be false
      end
    end

    describe "#add_message" do
      it "appends message to messages array" do
        conversation = create(:agent_conversation)

        conversation.add_message(role: "user", content: "Hello")

        expect(conversation.messages.last["role"]).to eq("user")
        expect(conversation.messages.last["content"]).to eq("Hello")
        expect(conversation.messages.last["timestamp"]).to be_present
      end

      it "updates last_message_at" do
        conversation = create(:agent_conversation)

        expect {
          conversation.add_message(role: "user", content: "Hello")
        }.to change { conversation.last_message_at }
      end

      it "saves the conversation" do
        conversation = create(:agent_conversation)
        conversation.add_message(role: "user", content: "Hello")

        conversation.reload
        expect(conversation.messages.length).to eq(1)
      end
    end

    describe "#extend_expiration" do
      it "extends expiration by configured TTL" do
        agent = create(:deployed_agent, deployment_config: {
          conversation_ttl: 3600
        })
        conversation = create(:agent_conversation, deployed_agent: agent, expires_at: 30.minutes.from_now)

        conversation.extend_expiration

        expect(conversation.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      end
    end

    describe "#message_count" do
      it "returns the number of messages" do
        conversation = create(:agent_conversation, :with_messages)
        expect(conversation.message_count).to eq(3)
      end

      it "returns 0 for empty conversations" do
        conversation = create(:agent_conversation)
        expect(conversation.message_count).to eq(0)
      end
    end

    describe "#last_user_message" do
      it "returns the last user message" do
        conversation = create(:agent_conversation, :with_messages)
        last_user = conversation.last_user_message

        expect(last_user["role"]).to eq("user")
        expect(last_user["content"]).to eq("I can't log in")
      end

      it "returns nil when no user messages" do
        conversation = create(:agent_conversation)
        expect(conversation.last_user_message).to be_nil
      end
    end
  end
end
