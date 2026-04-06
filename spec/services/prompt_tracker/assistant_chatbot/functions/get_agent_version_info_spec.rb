# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Functions::GetAgentVersionInfo do
  let(:agent) { create(:agent, :with_active_version) }
  let(:agent_version) { agent.active_version }
  let(:context) { {} }

  subject(:function) { described_class.new({ agent_version_id: agent_version.id }, context) }

  describe "#call" do
    it "returns a summary for the agent version" do
      result = function.call

      expect(result.success?).to be true
      expect(result.message).to include("Agent Version Information")
      expect(result.message).to include(agent.name)
      expect(result.entities_created[:agent_version_id]).to eq(agent_version.id)
      expect(result.entities_created[:agent_id]).to eq(agent.id)
      expect(result.links).to be_present
    end

    it "returns a failure result when agent_version_id is missing" do
      result = described_class.new({}, context).call

      expect(result.success?).to be false
      expect(result.error).to include("agent_version_id is required")
    end
  end
end
