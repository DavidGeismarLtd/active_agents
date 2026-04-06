# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Functions::GenerateTests do
  let(:agent) { create(:agent, :with_active_version) }
  let(:version) { agent.active_version }

  it "returns only a 'View all tests' link" do
    tests = [
      create(:test, testable: version, name: "test_one", description: "desc"),
      create(:test, testable: version, name: "test_two", description: "desc")
    ]

    allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return(
      { count: 2, tests: tests, overall_reasoning: "reason" }
    )

    result = described_class.new({ agent_version_id: version.id, count: 2 }, {}).call

    expect(result.success?).to be true
    expect(result.links.length).to eq(1)
    expect(result.links.first[:text]).to eq("View all tests")
    expect(result.links.first[:url]).to eq("/prompt_tracker/testing/agents/#{agent.id}/versions/#{version.id}#tests")
  end
end
